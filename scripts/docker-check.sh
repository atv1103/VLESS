#!/bin/bash
set -e

if command -v docker >/dev/null 2>&1; then
  echo "Docker already installed"
else
  echo "Docker not found, installing..."

  sudo apt update
  sudo apt install -y curl

  curl -fsSL https://get.docker.com | sudo sh

  sudo systemctl enable docker
  sudo systemctl start docker

  sudo usermod -aG docker "${SUDO_USER:-$USER}"

  echo "Docker installed successfully"
  echo "Please logout/login to use docker without sudo"
fi



