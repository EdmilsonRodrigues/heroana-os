#!/usr/bin/env bash
uptime -p | sed -e 's/up //g'
