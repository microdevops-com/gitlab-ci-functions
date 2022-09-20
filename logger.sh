#!/bin/bash

set -euo pipefail

function log_color() {
  local color_code="$1"
  shift

  stdbuf -oL -eL printf "\033[${color_code}m%s\033[0m\n" "$*" >&2
}

function log_red() {
  log_color "0;31" "$@"
}

function log_blue() {
  log_color "0;34" "$@"
}

function log_green() {
  log_color "1;32" "$@"
}

function log_yellow() {
  log_color "1;33" "$@"
}

function log_task() {
  log_blue "🔃" "$@"
}

function log_manual_action() {
  log_red "⚠️" "$@"
}

function log_command() {
  log_yellow "👉" "$@"
}


function log_error() {
  log_red "❌" "$@"
}

function log_info() {
  log_blue "ℹ️" "$@"
}

function error() {
  log_error "$@"
  exit 1
}

function log_prefix_output() {
  local prefix="$1"
  local color_code="$2"
  shift 2

  local sed_replace
  sed_replace=$(printf "\033[${color_code}m%s: &\033[0m" "${prefix}")

  # shellcheck disable=SC2312
  stdbuf -oL -eL "$@" &> >(sed "s,^.*$,${sed_replace}," >&2)
}