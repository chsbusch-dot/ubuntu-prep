#!/bin/bash

SCRIPT_NAME="ubuntu-prep-setup.sh"

echo -e "\e[1;34m===== 1. Running Local ShellCheck =====\e[0m"
if command -v shellcheck &> /dev/null; then
    # We ignore SC2155 (declare and assign separately) and SC2086 (double quote to prevent globbing) 
    # to avoid spamming the console for stylistic choices.
    shellcheck -e SC2155,SC2086 "$SCRIPT_NAME"
    echo "✅ ShellCheck completed."
else
    echo "⚠️ ShellCheck is not installed locally. Skipping static analysis."
fi

echo -e "\n\e[1;34m===== 2. Running isolated Docker execution test =====\e[0m"
# This spins up a clean Ubuntu 22.04 image, maps your script into it, and tests it.
docker run --rm -i -v "$(pwd)/$SCRIPT_NAME:/script.sh" ubuntu:22.04 bash -c "
    echo '-> Updating apt and installing base test dependencies...'
    apt-get update -qq && apt-get install -y sudo curl file jq procps
    
    echo '-> Running syntax check (bash -n)...'
    bash -n /script.sh
    if [ \$? -eq 0 ]; then echo '✅ Syntax check passed!'; else exit 1; fi
    
    echo '-> Adding test user to simulate real environment...'
    useradd -m testuser && usermod -aG sudo testuser
    echo 'testuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
    
    # (Optional) You can pipe inputs to test the menus, or run individual functions here.
"