#!/bin/bash

echo "Welcome to the Nillion Verifier auto-installer"

cd $HOME

# Обновляем систему и устанавливаем зависимости
echo "Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y jq curl gnupg screen

# Проверка, выполняется ли скрипт в screen
if [ -z "$STY" ]; then
    echo "Starting the script in a new screen session..."
    # Запускаем новую screen-сессию для выполнения дальнейших шагов
    screen -S nillion_installer -dm bash -c "$0 --run-in-screen"
    echo "Script launched in a new screen session 'nillion_installer'."
    exit
fi

# Запуск выполнения в screen-сессии
if [ "$1" == "--run-in-screen" ]; then
    echo "Screen session is active, proceeding with Docker setup and accuser initialization..."

    # Установка Docker
    if ! command -v docker &> /dev/null; then
        echo "Docker is not installed. Installing Docker..."
        sudo apt-get remove -y docker docker-engine docker.io containerd runc

        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io
    else
        echo "Docker is already installed, skipping installation..."
    fi

    echo "Pulling the accuser image from Docker Hub..."
    docker pull nillion/retailtoken-accuser:v1.0.0

    echo "Initializing the accuser..."
    mkdir -p nillion/accuser
    docker run -v $(pwd)/nillion/accuser:/var/tmp nillion/retailtoken-accuser:v1.0.0 initialise

    echo "Displaying accuser credentials:"
    credentials_file="nillion/accuser/credentials.json"
    if [ -f "$credentials_file" ]; then
        address=$(jq -r '.address' $credentials_file)
        pub_key=$(jq -r '.pub_key' $credentials_file)
        priv_key=$(jq -r '.priv_key' "$credentials_file")
        echo "Address: $address"
        echo "Public Key: $pub_key"
        echo "Private Key: $priv_key"
    else
        echo "credentials.json not found!"
    fi

    while true; do
        echo "Please copy your account_id and public_key to https://verifier.nillion.com/verifier."
        read -p "Have you completed this step? (y/n): " copied_details
        if [ "$copied_details" == "y" ]; then
            break
        else
            echo "Waiting for you to copy your account_id and public_key..."
        fi
    done

    while true; do
        echo "Please fund your accuser address (account_id) on https://faucet.testnet.nillion.com/."
        read -p "Have you funded your accuser address? (y/n): " funded_accuser
        if [ "$funded_accuser" == "y" ]; then
            break
        else
            echo "Waiting for you to fund your accuser address..."
        fi
    done

    current_height=$(curl -s https://testnet-nillion-rpc.lavenderfive.com/abci_info | jq -r '.result.response.last_block_height')
    block_start=$((current_height - 100))

    echo "Automatically determined block start is $block_start"

    sleep_time=$((10 + RANDOM % 15))m
    echo "Sleeping for $sleep_time..."
    sleep $sleep_time

    echo "Running the accuser..."
    docker run -v ./nillion/accuser:/var/tmp nillion/retailtoken-accuser:v1.0.0 accuse --rpc-endpoint "https://testnet-nillion-rpc.lavenderfive.com" --block-start $block_start
else
    echo "Script running outside of screen, no further actions."
fi
