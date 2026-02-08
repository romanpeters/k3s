#!/usr/bin/env bash
set -euo pipefail

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    return 1
  fi
}

install_with_brew() {
  echo "Installing tools with Homebrew..."
  brew update
  brew install yamllint pre-commit kubeconform kustomize yamlfmt
}

install_with_apt() {
  echo "Installing tools with apt..."
  sudo apt-get update
  sudo apt-get install -y yamllint pre-commit

  # kustomize
  if ! need kustomize; then
    curl -sSL https://github.com/kubernetes-sigs/kustomize/releases/latest/download/kustomize_linux_amd64.tar.gz \
      | sudo tar -xz -C /usr/local/bin
  fi

  # kubeconform
  if ! need kubeconform; then
    curl -sSL https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz \
      | sudo tar -xz -C /usr/local/bin
  fi

  # yamlfmt
  if ! need yamlfmt; then
    if ! need go; then
      sudo apt-get install -y golang-go
    fi
    mkdir -p "$HOME/bin"
    GOBIN="$HOME/bin" go install github.com/google/yamlfmt/cmd/yamlfmt@v0.9.0
    echo "Installed yamlfmt to $HOME/bin (ensure it is in your PATH)."
  fi
}

if need brew; then
  install_with_brew
elif need apt-get; then
  install_with_apt
else
  echo "No supported package manager found (brew or apt-get)." >&2
  echo "Please install these tools manually: yamllint, pre-commit, kubeconform, kustomize, yamlfmt" >&2
  exit 1
fi

echo "Done. Next steps:"
if need pre-commit; then
  echo "  pre-commit install"
  echo "  pre-commit run --all-files"
fi
