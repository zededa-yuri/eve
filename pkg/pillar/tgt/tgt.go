// Copyright (c) 2021 Zededa, Inc.
// SPDX-License-Identifier: Apache-2.0

package tgt

import (
	"fmt"
	"io/ioutil"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/sirupsen/logrus"
)

const (
	tgtPath    = "/hostfs/sys/kernel/config/target"
	iBlockPath = tgtPath + "/core/iblock_0"
	naaPrefix  = "5001405" // from rtslib-fb
)

func waitForFile(fileName string) error {
	maxDelay := time.Second * 5
	delay := time.Millisecond * 500
	var waited time.Duration
	for {
		if delay != 0 {
			time.Sleep(delay)
			waited += delay
		}
		if _, err := os.Stat(fileName); err == nil {
			return nil
		} else {
			if waited > maxDelay {
				return fmt.Errorf("file not found: error %v", err)
			}
			delay = 2 * delay
			if delay > maxDelay {
				delay = maxDelay
			}
		}
	}
}

//CheckTargetIBlock check target iblock exists
func CheckTargetIBlock(tgtName string) bool {
	targetRoot := filepath.Join(iBlockPath, tgtName)
	if _, err := os.Stat(targetRoot); err == nil {
		return true
	}
	return false
}

// TargetCreateIBlock - Create iblock target for device
func TargetCreateIBlock(dev, tgtName, serial string) error {
	targetRoot := filepath.Join(iBlockPath, tgtName)
	err := os.MkdirAll(targetRoot, os.ModeDir)
	if err != nil {
		return fmt.Errorf("cannot create fileio: %v", err)
	}
	if err := waitForFile(filepath.Join(targetRoot, "control")); err != nil {
		return fmt.Errorf("error waitForFile: %v", err)
	}
	controlCommand := fmt.Sprintf("udev_path=%s", dev)
	if err := ioutil.WriteFile(filepath.Join(targetRoot, "control"), []byte(controlCommand), 0660); err != nil {
		return fmt.Errorf("error set control: %v", err)
	}
	if err := ioutil.WriteFile(filepath.Join(targetRoot, "wwn", "vpd_unit_serial"), []byte(serial), 0660); err != nil {
		return fmt.Errorf("error set vpd_unit_serial: %v", err)
	}
	if err := ioutil.WriteFile(filepath.Join(targetRoot, "enable"), []byte("1"), 0660); err != nil {
		return fmt.Errorf("error set enable: %v", err)
	}
	return nil
}

//GenerateNaaSerial generates naa serial
func GenerateNaaSerial() string {
	rand.Seed(time.Now().UnixNano())
	return fmt.Sprintf("%s%09x", naaPrefix, rand.Uint32())
}

// VHostCreateIBlock - Create vHost fabric
func VHostCreateIBlock(tgtName, wwn string) error {
	targetRoot := filepath.Join(iBlockPath, tgtName)
	if _, err := os.Stat(targetRoot); err != nil {
		return fmt.Errorf("tgt access error (%s): %s", targetRoot, err)
	}
	vhostRoot := filepath.Join(tgtPath, "vhost", wwn, "tpgt_1")
	vhostLun := filepath.Join(vhostRoot, "lun", "lun_0")
	err := os.MkdirAll(vhostLun, os.ModeDir)
	if err != nil {
		return fmt.Errorf("cannot create vhost: %v", err)
	}
	controlCommand := "scsi_host_id=1,scsi_channel_id=0,scsi_target_id=0,scsi_lun_id=0"
	if err := ioutil.WriteFile(filepath.Join(targetRoot, "control"), []byte(controlCommand), 0660); err != nil {
		return fmt.Errorf("error set control: %v", err)
	}
	if err := waitForFile(filepath.Join(vhostRoot, "nexus")); err != nil {
		return fmt.Errorf("error waitForFile: %v", err)
	}
	if err := ioutil.WriteFile(filepath.Join(vhostRoot, "nexus"), []byte(wwn), 0660); err != nil {
		return fmt.Errorf("error set nexus: %v", err)
	}
	if _, err := os.Stat(filepath.Join(vhostLun, "iblock")); os.IsNotExist(err) {
		if err := os.Symlink(targetRoot, filepath.Join(vhostLun, "iblock")); err != nil {
			return fmt.Errorf("error create symlink: %v", err)
		}
	}
	return nil
}

func getSerialTarget(tgtName string) (string, error) {
	targetRoot := filepath.Join(iBlockPath, tgtName)
	serial, err := ioutil.ReadFile(filepath.Join(targetRoot, "wwn", "vpd_unit_serial"))
	return strings.TrimSpace(string(serial)), err
}

//CheckVHostIBlock check target vhost exists
func CheckVHostIBlock(tgtName string) bool {
	serial, err := getSerialTarget(tgtName)
	if err != nil {
		logrus.Errorf("CheckVHostIBlock (%s): %v", tgtName, err)
		return false
	}
	vhostRoot := filepath.Join(tgtPath, "vhost", fmt.Sprintf("naa.%s", serial), "tpgt_1")
	vhostLun := filepath.Join(vhostRoot, "lun", "lun_0")
	if _, err := os.Stat(filepath.Join(vhostLun, "iblock")); err == nil {
		return true
	}
	return false
}

// VHostDeleteIBlock - delete
func VHostDeleteIBlock(tgtName, wwn string) error {
	vhostRoot := filepath.Join(tgtPath, "vhost", wwn, "tpgt_1")
	vhostLun := filepath.Join(vhostRoot, "lun", "lun_0")
	if _, err := os.Stat(vhostLun); os.IsNotExist(err) {
		return fmt.Errorf("vHost do not exists for tgtName %s: %s", tgtName, err)
	}
	if err := os.Remove(filepath.Join(vhostLun, "iblock")); err != nil {
		return fmt.Errorf("error delete symlink: %v", err)
	}
	if err := os.RemoveAll(vhostLun); err != nil {
		return fmt.Errorf("error delete lun: %v", err)
	}
	if err := os.RemoveAll(vhostRoot); err != nil {
		return fmt.Errorf("error delete lun: %v", err)
	}
	if err := os.RemoveAll(filepath.Dir(vhostRoot)); err != nil {
		return fmt.Errorf("error delete lun: %v", err)
	}
	return nil
}

// TargetDeleteIBlock - Delete iblock target
func TargetDeleteIBlock(tgtName string) error {
	targetRoot := filepath.Join(iBlockPath, tgtName)
	if _, err := os.Stat(targetRoot); os.IsNotExist(err) {
		return fmt.Errorf("tgt do not exists for tgtName %s: %s", tgtName, err)
	}
	if err := os.RemoveAll(targetRoot); err != nil {
		return fmt.Errorf("error delete tgt: %v", err)
	}
	return nil
}
