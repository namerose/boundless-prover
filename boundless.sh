#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Add error handling to prevent terminal from closing unexpectedly
set -euo pipefail
trap 'echo -e "${RED}[ERROR]${NC} Command failed at line $LINENO with exit code $?. Press Enter to continue..."; read' ERR
trap 'echo -e "\n${BLUE}[INFO]${NC} Script execution interrupted. Press Enter to exit..."; read' INT TERM

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    print_error "This script must be run as root. Please use 'su -' or login as root."
    echo "Press Enter to exit..."
    read
    exit 1
fi

print_step "Installing basic dependencies (apt, curl, git)..."
apt update || { 
    print_error "Failed to run 'apt update'. Do you have internet connectivity?"
    echo "Press Enter to exit..."
    read
    exit 1
}

apt install -y sudo git curl || {
    print_error "Failed to install basic packages. Do you have proper permissions?"
    echo "Press Enter to exit..."
    read
    exit 1
}

# Verify installation
if ! command -v git &> /dev/null || ! command -v curl &> /dev/null; then
    print_error "Failed to install git or curl. Please check system requirements."
    echo "Press Enter to exit..."
    read
    exit 1
fi

print_success "Basic dependencies installed"

print_step "Cloning Boundless repository..."
git clone https://github.com/boundless-xyz/boundless || {
    print_error "Failed to clone the repository. Check your internet connection."
    echo "Press Enter to exit..."
    read
    exit 1
}

cd boundless || {
    print_error "Failed to enter boundless directory."
    echo "Press Enter to exit..."
    read
    exit 1
}

git checkout release-0.10 || {
    print_error "Failed to checkout release-0.10 branch."
    echo "Press Enter to exit..."
    read
    exit 1
}

print_success "Repository cloned and checked out to release-0.10"

print_step "Replacing setup script..."
# First ensure the scripts directory exists
if [ ! -d "scripts" ]; then
    mkdir -p scripts || {
        print_error "Failed to create scripts directory."
        echo "Press Enter to exit..."
        read
        exit 1
    }
fi

rm -f scripts/setup.sh
curl -o scripts/setup.sh https://raw.githubusercontent.com/zunxbt/boundless-prover/refs/heads/main/script.sh || {
    print_error "Failed to download setup script."
    echo "Press Enter to exit..."
    read
    exit 1
}

chmod +x scripts/setup.sh || {
    print_error "Failed to make setup script executable."
    echo "Press Enter to exit..."
    read
    exit 1
}

print_success "Setup script replaced"

print_step "Running setup script..."
./scripts/setup.sh || {
    print_error "Setup script failed. Check the error messages above."
    echo "Press Enter to exit..."
    read
    exit 1
}
print_success "Setup script executed"

print_step "Installing Rust..."
if command -v rustc &> /dev/null && command -v cargo &> /dev/null; then
    print_success "Rust is already installed"
else
    print_info "Installing Rust programming language..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || {
        print_error "Failed to install Rust. Trying alternate method..."
        apt install -y rustc cargo || {
            print_error "Failed to install Rust via apt. Press Enter to exit..."
            read
            exit 1
        }
    }
    
    # Source rust environment after installation
    if [[ -f "$HOME/.cargo/env" ]]; then
        source "$HOME/.cargo/env"
        print_success "Rust installed successfully."
    else
        print_error "Rust installation failed. ~/.cargo/env not found. Press Enter to exit..."
        read
        exit 1
    fi
fi

# Make sure rust binaries are in PATH
export PATH="$HOME/.cargo/bin:$PATH"

# Verify rust installation
if command -v rustc &> /dev/null && command -v cargo &> /dev/null; then
    print_info "Rust version: $(rustc --version)"
    print_info "Cargo version: $(cargo --version)"
else
    print_error "Rust verification failed. Installation might have issues. Press Enter to exit..."
    read
    exit 1
fi

print_step "Installing Risc Zero..."
curl -L https://risczero.com/install | bash

export PATH="$HOME/.risc0/bin:$PATH"
echo "Added $HOME/.risc0/bin to PATH"

if [[ -d "$HOME/.rzup/bin" ]]; then
    export PATH="$HOME/.rzup/bin:$PATH"
    echo "Added $HOME/.rzup/bin to PATH"
fi

if [[ -f "$HOME/.bashrc" ]]; then
    source "$HOME/.bashrc"
fi

if [[ -f "$HOME/.rzup/env" ]]; then
    source "$HOME/.rzup/env"
    echo "Sourced rzup environment from $HOME/.rzup/env"
fi

if [[ -f "/root/.risc0/env" ]]; then
    source "/root/.risc0/env"
    echo "Sourced rzup environment from /root/.risc0/env"
fi

if command -v rzup &> /dev/null; then
    echo "rzup found, installing Rust toolchain..."
    rzup install rust
    echo "Updating r0vm..."
    rzup update r0vm
    print_success "Risc Zero installed successfully"
else
    echo "rzup not found. Checking available paths..."
    echo "Current PATH: $PATH"
    echo "Contents of /root/.risc0/bin:"
    ls -la /root/.risc0/bin/ 2>/dev/null || echo "Directory not found"
    
    if [[ -x "/root/.risc0/bin/rzup" ]]; then
        echo "Found rzup binary, executing directly..."
        /root/.risc0/bin/rzup install rust
        /root/.risc0/bin/rzup update r0vm
        print_success "Risc Zero installed successfully using direct path"
    else
        print_error "rzup binary not found or not executable"
    fi
fi

# Make sure rust environment is sourced
if [[ -f "$HOME/.cargo/env" ]]; then
    source "$HOME/.cargo/env"
fi

print_step "Installing additional tools..."

if ! command -v cargo &> /dev/null; then
    print_error "Cargo not found after installation attempts. Press Enter to exit..."
    read
    exit 1
fi

echo "Installing bento-client..."
cargo install --git https://github.com/risc0/risc0 bento-client --bin bento_cli || {
    print_error "Failed to install bento-client. Press Enter to continue anyway..."
    read
}

if command -v just &> /dev/null; then
    echo "Running just bento..."
    just bento || print_warning "just bento command failed, continuing anyway"
else
    print_warning "just command not found, installing..."
    curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin || {
        print_warning "Failed to install just, continuing anyway"
    }
    
    if command -v just &> /dev/null; then
        just bento || print_warning "just bento command failed, continuing anyway"
    else
        print_warning "just command still not available, continuing anyway"
    fi
fi

echo "Installing boundless-cli..."
cargo install --locked boundless-cli || {
    print_error "Failed to install boundless-cli. This is critical. Press Enter to exit..."
    read
    exit 1
}

print_success "Additional tools installed"

print_step "Checking GPU configuration..."
gpu_count=0
if command -v nvidia-smi &> /dev/null; then
    gpu_count=$(nvidia-smi -L 2>/dev/null | wc -l)
fi
echo "Found $gpu_count GPU(s)"

cd boundless

# Modify compose for multiple GPUs function included from the original script
modify_compose_for_multiple_gpus() {
    local gpu_count="$1"
    
    if [ $gpu_count -le 1 ]; then
        echo "Single GPU detected, no compose.yml modification needed"
        return 0
    fi
    
    print_step "Configuring compose.yml for $gpu_count GPUs..."
    
    cp compose.yml compose.yml.backup
    echo "Created backup: compose.yml.backup"
    
    echo "Adding GPU agents for GPUs 1-$((gpu_count-1))..."
    
    local gpu_agent_end_line
    gpu_agent_end_line=$(grep -n "capabilities: \[gpu\]" compose.yml | head -1 | cut -d: -f1)
    
    if [[ -z "$gpu_agent_end_line" ]]; then
        print_error "Could not find gpu_prove_agent0 section end marker"
        return 1
    fi
    
    echo "Found gpu_prove_agent0 end at line $gpu_agent_end_line"
    
    local additional_agents=""
    for ((i=1; i<gpu_count; i++)); do
        additional_agents+="
  gpu_prove_agent$i:
    <<: *agent-common
    runtime: nvidia
    mem_limit: 4G
    cpus: 4
    entrypoint: /app/agent -t prove

    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ['$i']
              capabilities: [gpu]
"
    done
    
    {
        head -n "$gpu_agent_end_line" compose.yml
        echo "$additional_agents"
        tail -n +$((gpu_agent_end_line + 1)) compose.yml
    } > compose.yml.tmp && mv compose.yml.tmp compose.yml
    
    print_success "Added GPU agents for GPUs 1-$((gpu_count-1))"
    
    echo "Updating broker dependencies..."
    
    local broker_start_line
    local depends_on_line
    local depends_on_end_line
    
    broker_start_line=$(grep -n "^[[:space:]]*broker:" compose.yml | cut -d: -f1)
    if [[ -z "$broker_start_line" ]]; then
        print_error "Could not find broker section"
        return 1
    fi
    
    depends_on_line=$(tail -n +$broker_start_line compose.yml | grep -n "^[[:space:]]*depends_on:" | head -1 | cut -d: -f1)
    if [[ -z "$depends_on_line" ]]; then
        print_error "Could not find broker depends_on section"
        return 1
    fi
    
    depends_on_line=$((broker_start_line + depends_on_line - 1))
    echo "Found broker depends_on at line $depends_on_line"
    
    depends_on_end_line=$depends_on_line
    while read -r line; do
        ((depends_on_end_line++))
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
            continue
        elif [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        elif [[ "$line" =~ ^[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]* ]]; then
            ((depends_on_end_line--))
            break
        elif [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]* ]]; then
            ((depends_on_end_line--))
            break
        fi
    done < <(tail -n +$((depends_on_line + 1)) compose.yml)
    
    echo "Dependencies section ends at line $depends_on_end_line"
    
    local new_dependencies="    depends_on:
      - rest_api"
    
    for ((i=0; i<gpu_count; i++)); do
        new_dependencies+="
      - gpu_prove_agent$i"
    done
    
    new_dependencies+="
      - exec_agent0
      - exec_agent1
      - aux_agent
      - snark_agent
      - redis
      - postgres"
    
    {
        head -n $((depends_on_line - 1)) compose.yml
        echo "$new_dependencies"
        tail -n +$((depends_on_end_line + 1)) compose.yml
    } > compose.yml.tmp && mv compose.yml.tmp compose.yml
    
    print_success "Updated broker dependencies to include all $gpu_count GPU agents"
    print_success "Multi-GPU configuration completed successfully"
}

modify_compose_for_multiple_gpus $gpu_count

print_step "Network Selection"
echo -e "${YELLOW}Choose networks to run the prover on:${NC}"
echo "1. Base Mainnet"
echo "2. Base Sepolia"
echo "3. Ethereum Sepolia"
echo ""
read -p "Enter your choices (e.g., 1,2,3 for all): " network_choice

# Function to update environment variables
update_env_var() {
    local file="$1"
    local var="$2"
    local value="$3"
    
    if grep -q "^${var}=" "$file"; then
        sed -i "s|^${var}=.*|${var}=${value}|" "$file"
    else
        echo "${var}=${value}" >> "$file"
    fi
}

if [[ $network_choice == *"1"* ]]; then
    cp .env.broker-template .env.broker.base
    cp .env.base .env.base.backup
    echo "Created Base Mainnet environment files"
fi

if [[ $network_choice == *"2"* ]]; then
    cp .env.broker-template .env.broker.base-sepolia
    cp .env.base-sepolia .env.base-sepolia.backup
    echo "Created Base Sepolia environment files"
fi

if [[ $network_choice == *"3"* ]]; then
    cp .env.broker-template .env.broker.eth-sepolia
    cp .env.eth-sepolia .env.eth-sepolia.backup
    echo "Created Ethereum Sepolia environment files"
fi

read -p "Enter your private key: " private_key

if [[ $network_choice == *"1"* ]]; then
    read -p "Enter Base Mainnet RPC URL: " base_rpc
    
    update_env_var ".env.broker.base" "PRIVATE_KEY" "$private_key"
    update_env_var ".env.broker.base" "BOUNDLESS_MARKET_ADDRESS" "0x26759dbB201aFbA361Bec78E097Aa3942B0b4AB8"
    update_env_var ".env.broker.base" "SET_VERIFIER_ADDRESS" "0x8C5a8b5cC272Fe2b74D18843CF9C3aCBc952a760"
    update_env_var ".env.broker.base" "RPC_URL" "$base_rpc"
    update_env_var ".env.broker.base" "ORDER_STREAM_URL" "https://base-mainnet.beboundless.xyz"
    
    echo "export PRIVATE_KEY=\"$private_key\"" >> .env.base
    echo "export RPC_URL=\"$base_rpc\"" >> .env.base
    
    print_success "Base Mainnet environment configured"
fi

if [[ $network_choice == *"2"* ]]; then
    read -p "Enter Base Sepolia RPC URL: " base_sepolia_rpc
    
    update_env_var ".env.broker.base-sepolia" "PRIVATE_KEY" "$private_key"
    update_env_var ".env.broker.base-sepolia" "BOUNDLESS_MARKET_ADDRESS" "0x6B7ABa661041164b8dB98E30AE1454d2e9D5f14b"
    update_env_var ".env.broker.base-sepolia" "SET_VERIFIER_ADDRESS" "0x8C5a8b5cC272Fe2b74D18843CF9C3aCBc952a760"
    update_env_var ".env.broker.base-sepolia" "RPC_URL" "$base_sepolia_rpc"
    update_env_var ".env.broker.base-sepolia" "ORDER_STREAM_URL" "https://base-sepolia.beboundless.xyz"
    
    echo "export PRIVATE_KEY=\"$private_key\"" >> .env.base-sepolia
    echo "export RPC_URL=\"$base_sepolia_rpc\"" >> .env.base-sepolia
    
    print_success "Base Sepolia environment configured"
fi

if [[ $network_choice == *"3"* ]]; then
    read -p "Enter Ethereum Sepolia RPC URL: " eth_sepolia_rpc
    
    update_env_var ".env.broker.eth-sepolia" "PRIVATE_KEY" "$private_key"
    update_env_var ".env.broker.eth-sepolia" "BOUNDLESS_MARKET_ADDRESS" "0x13337C76fE2d1750246B68781ecEe164643b98Ec"
    update_env_var ".env.broker.eth-sepolia" "SET_VERIFIER_ADDRESS" "0x7aAB646f23D1392d4522CFaB0b7FB5eaf6821d64"
    update_env_var ".env.broker.eth-sepolia" "RPC_URL" "$eth_sepolia_rpc"
    update_env_var ".env.broker.eth-sepolia" "ORDER_STREAM_URL" "https://eth-sepolia.beboundless.xyz/"
    
    echo "export PRIVATE_KEY=\"$private_key\"" >> .env.eth-sepolia
    echo "export RPC_URL=\"$eth_sepolia_rpc\"" >> .env.eth-sepolia
    
    print_success "Ethereum Sepolia environment configured"
fi

print_step "Configuring broker settings..."
cp broker-template.toml broker.toml

if [ $gpu_count -eq 1 ]; then
    max_proofs=2
    peak_khz=100
elif [ $gpu_count -eq 2 ]; then
    max_proofs=4
    peak_khz=200
elif [ $gpu_count -eq 3 ]; then
    max_proofs=6
    peak_khz=300
else
    max_proofs=$((gpu_count * 2))
    peak_khz=$((gpu_count * 100))
fi

sed -i "s/max_concurrent_proofs = .*/max_concurrent_proofs = $max_proofs/" broker.toml
sed -i "s/peak_prove_khz = .*/peak_prove_khz = $peak_khz/" broker.toml

print_success "Broker settings configured for $gpu_count GPU(s)"

print_step "Depositing stake for selected networks..."

if [[ $network_choice == *"1"* ]]; then
    echo "Depositing stake on Base Mainnet..."
    boundless \
        --rpc-url $base_rpc \
        --private-key $private_key \
        --chain-id 8453 \
        --boundless-market-address 0x26759dbB201aFbA361Bec78E097Aa3942B0b4AB8 \
        --set-verifier-address 0x8C5a8b5cC272Fe2b74D18843CF9C3aCBc952a760 \
        account deposit-stake 10
    print_success "Base Mainnet stake deposited"
fi

if [[ $network_choice == *"2"* ]]; then
    echo "Depositing stake on Base Sepolia..."
    boundless \
        --rpc-url $base_sepolia_rpc \
        --private-key $private_key \
        --chain-id 84532 \
        --boundless-market-address 0x6B7ABa661041164b8dB98E30AE1454d2e9D5f14b \
        --set-verifier-address 0x8C5a8b5cC272Fe2b74D18843CF9C3aCBc952a760 \
        account deposit-stake 10
    print_success "Base Sepolia stake deposited"
fi

if [[ $network_choice == *"3"* ]]; then
    echo "Depositing stake on Ethereum Sepolia..."
    boundless \
        --rpc-url $eth_sepolia_rpc \
        --private-key $private_key \
        --chain-id 11155111 \
        --boundless-market-address 0x13337C76fE2d1750246B68781ecEe164643b98Ec \
        --set-verifier-address 0x7aAB646f23D1392d4522CFaB0b7FB5eaf6821d64 \
        account deposit-stake 10
    print_success "Ethereum Sepolia stake deposited"
fi

print_success "Stake deposits completed for all selected networks"

print_step "Setting up environment for future sessions..."

{
    echo ""
    echo "# Rust environment"
    echo "if [ -f \"\$HOME/.cargo/env\" ]; then"
    echo "    source \"\$HOME/.cargo/env\""
    echo "fi"
    echo ""
    echo "# RISC Zero environment"
    echo "export PATH=\"/root/.risc0/bin:\$PATH\""
    echo "if [ -f \"\$HOME/.rzup/env\" ]; then"
    echo "    source \"\$HOME/.rzup/env\""
    echo "fi"
    echo "if [ -f \"/root/.risc0/env\" ]; then"
    echo "    source \"/root/.risc0/env\""
    echo "fi"
} >> ~/.bashrc

print_success "Environment configured for future sessions"

print_step "Starting brokers..."

if [[ $network_choice == *"1"* ]]; then
    echo "Starting Base Mainnet broker..."
    just broker up ./.env.broker.base
fi

if [[ $network_choice == *"2"* ]]; then
    echo "Starting Base Sepolia broker..."
    just broker up ./.env.broker.base-sepolia
fi

if [[ $network_choice == *"3"* ]]; then
    echo "Starting Ethereum Sepolia broker..."
    just broker up ./.env.broker.eth-sepolia
fi

print_success "Setup completed successfully!"
print_success "To check logs, use: docker compose logs -f broker"
print_success "Follow the instructions in the README.md for additional commands and operations."

# Keep terminal open at the end of the script
echo -e "\n${GREEN}[INFO]${NC} Installation process complete. Press Enter to exit..."
read
