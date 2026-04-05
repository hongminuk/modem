#!/bin/bash
cd "$(dirname "$0")"
vivado -mode batch -source create_project.tcl
