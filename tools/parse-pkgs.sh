#!/bin/bash -u
# Poor man's[1] yml generator
#
#
# [1] A poor man is a man on a deadline.
#
EVE="$(cd "$(dirname "$0")" && pwd)/../"
PATH="$EVE/build-tools/bin:$PATH"

get_git_tag() {
  echo ${EVE_HASH:-$(git tag -l --points-at HEAD | grep '[0-9]*\.[0-9]*\.[0-9]*' | head -1)}
}

linuxkit_tag() {
    echo "$(linuxkit pkg show-tag ${EVE_HASH:+--hash $EVE_HASH} "$EVE/$1")$ARCH"
}

immutable_tag() {
  # we have to resolve symbolic tags like x.y.z or snapshot to something immutable
  # so that we can detect when the symbolic tag starts pointing a different immutable
  # object and thus trigger a new SHA for things like EVE
  echo $(docker inspect --format='{{.Id}}' "$1" 2>/dev/null ||
         docker inspect --format='{{index .RepoDigests 0}}' "$1" 2>/dev/null ||
         echo "$1")
}

external_tag() {
  # Since the tag is external to us, we can't rely on local git SHAs,
  # thus the best we can do is:
  #    1. if we're building a release from a tag, we expect external tag to be the same
  #    2. if we're NOT building from a tag, the external tag is simply snapshot
  local TAG="`get_git_tag`"
  PKG="$1:${TAG:-snapshot}${ARCH}"

  # for external packages we have to always try to pull first - otherwise
  # we may have something stale in our local Docker cache
  docker pull "$PKG" 2>/dev/null >&2 || echo "WARNING: couldn't fetch the latest $PKG - may be using stale cache" >&2
  if docker inspect "$PKG" >/dev/null 2>&1 ; then
    echo "$PKG"
  else
    echo "WARNING: failed to obtain $PKG - using $2 instead" >&2
    echo $2
  fi
}

synthetic_tag() {
  NAME=$1
  shift 1
  # ignore undefined EVE_TAG in resolve_tags because not defined yet
  echo ${NAME}:${EVE_HASH:-$( (cat "$@" ; git rev-parse HEAD) | resolve_tags | git hash-object --stdin)}"$ARCH"
}

resolve_tags() {
  local tags="$1"
  local file="$2"
  local sedcmd
  sedcmd=$(echo "$tags" | sed -e "s/^/s#/g" -e "s/$/#g/g" -e "s/=/#/g")
  sed -e "$sedcmd" "${file:-}"
}

gen_tags() {
cat <<EOF
CURDIR=$(pwd)
ACRN_KERNEL_TAG=${ACRN_KERNEL_TAG}
NEW_KERNEL_TAG=${NEW_KERNEL_TAG}
KERNEL_TAG=${KERNEL_TAG}
FW_TAG=${FW_TAG}
XENTOOLS_TAG=${XENTOOLS_TAG}
DOM0ZTOOLS_TAG=${DOM0ZTOOLS_TAG}
RNGD_TAG=${RNGD_TAG}
XEN_TAG=${XEN_TAG}
ACRN_TAG=${ACRN_TAG}
DNSMASQ_TAG=${DNSMASQ_TAG}
STRONGSWAN_TAG=${STRONGSWAN_TAG}
TESTMSVCS_TAG=${TESTMSVCS_TAG}
PILLAR_TAG=${PILLAR_TAG}
STORAGE_INIT_TAG=${STORAGE_INIT_TAG}
DEV_OVERLAY_TAG=${DEV_OVERLAY_TAG}
WWAN_TAG=${WWAN_TAG}
WLAN_TAG=${WLAN_TAG}
GUACD_TAG=${GUACD_TAG}
GRUB_TAG=${GRUB_TAG}
GPTTOOLS_TAG=${GPTTOOLS_TAG}
NEWLOGD_TAG=${NEWLOGD_TAG}
WATCHDOG_TAG=${WATCHDOG_TAG}
MKRAW_TAG=${MKRAW_TAG}
MKISO_TAG=${MKISO_TAG}
MKCONF_TAG=${MKCONF_TAG}
DEBUG_TAG=${DEBUG_TAG}
LISP_TAG=${LISP_TAG}
VTPM_TAG=${VTPM_TAG}
UEFI_TAG=${UEFI_TAG}
EVE_TAG=${EVE_TAG:-}
KVMTOOLS_TAG=${KVMTOOLS_TAG}
IPXE_TAG=${IPXE_TAG}
EOF
}

if [ -z "$DOCKER_ARCH_TAG" ] ; then
  case $(uname -m) in
    x86_64) ARCH=-amd64
      ;;
    aarch64) ARCH=-arm64
      ;;
    *) echo "Unsupported architecture $(uname -m). Exiting" && exit 1
      ;;
  esac
else
  ARCH="-${DOCKER_ARCH_TAG}"
fi

KERNEL_TAG=$(linuxkit_tag pkg/kernel)
NEW_KERNEL_TAG=$(linuxkit_tag pkg/new-kernel)
ACRN_KERNEL_TAG=$(linuxkit_tag pkg/acrn-kernel)
FW_TAG=$(linuxkit_tag pkg/fw)
XENTOOLS_TAG=$(linuxkit_tag pkg/xen-tools)
XEN_TAG=$(linuxkit_tag pkg/xen)
ACRN_TAG=$(linuxkit_tag pkg/acrn)
GRUB_TAG=$(linuxkit_tag pkg/grub)
DNSMASQ_TAG=$(linuxkit_tag pkg/dnsmasq)
STRONGSWAN_TAG=$(linuxkit_tag pkg/strongswan)
TESTMSVCS_TAG=$(linuxkit_tag pkg/test-microsvcs)
DOM0ZTOOLS_TAG=$(linuxkit_tag pkg/dom0-ztools)
RNGD_TAG=$(linuxkit_tag pkg/rngd)
NEWLOGD_TAG=$(linuxkit_tag pkg/newlog)
WWAN_TAG=$(linuxkit_tag pkg/wwan)
WLAN_TAG=$(linuxkit_tag pkg/wlan)
GUACD_TAG=$(linuxkit_tag pkg/guacd)
LISP_TAG=$(linuxkit_tag pkg/lisp)
PILLAR_TAG=$(linuxkit_tag pkg/pillar)
DEV_OVERLAY_TAG=$(linuxkit_tag pkg/dev-overlay)
STORAGE_INIT_TAG=$(linuxkit_tag pkg/storage-init)
GPTTOOLS_TAG=$(linuxkit_tag pkg/gpt-tools)
WATCHDOG_TAG=$(linuxkit_tag pkg/watchdog)
MKRAW_TAG=$(linuxkit_tag pkg/mkimage-raw-efi)
MKISO_TAG=$(linuxkit_tag pkg/mkimage-iso-efi)
MKCONF_TAG=$(linuxkit_tag pkg/mkconf)
DEBUG_TAG=$(linuxkit_tag pkg/debug)
VTPM_TAG=$(linuxkit_tag pkg/vtpm)
UEFI_TAG=$(linuxkit_tag pkg/uefi)
KVMTOOLS_TAG=$(linuxkit_tag pkg/kvm-tools)
IPXE_TAG=$(linuxkit_tag pkg/ipxe)

# Synthetic tags: the following tags are based on hashing
# the contents of all the Dockerfile.in that we can find.
# That way, these tags are guaranteed to change whenever
# *any* *single* dependency changes.
#
# These tags need to be declared last sine they depend
# on the previous tags being already defined.
EVE_TAG=$(synthetic_tag zededa/eve pkg/pillar/Dockerfile.in)

TAGS=$(gen_tags)
if [ $# -ge 1 ]; then
  resolve_tags "$TAGS" "$1"
else
  echo "$TAGS"
fi
