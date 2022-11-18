set dotenv-load

all: install build

install:
    forge install

update:
    forge update

solc:
	pip3 install solc-select
	solc-select install 0.8.17
	solc-select use 0.8.17

build:
    forge build --force --build-info

test:
    forge test --force -vvv

clean:
    forge clean

gas-report:
    forge test --gas-report

flatten contract:
    forge flatten {{contract}}

slither contract:
    slither {{contract}}

format:
    prettier --write src/**/*.sol \
    && prettier --write src/*.sol \
    && prettier --write test/**/*.sol \
    && prettier --write test/*.sol \
    && prettier --write script/**/*.sol \
    && prettier --write script/*.sol

restore-submodules:
    #!/bin/sh
    set -e
    git config -f .gitmodules --get-regexp '^submodule\..*\.path$' |
        while read path_key path
        do
            url_key=$(echo $path_key | sed 's/\.path/.url/')
            url=$(git config -f .gitmodules --get "$url_key")
            git submodule add $url $path
        done

deploy:
    #!/bin/sh

    forge script "script/Deploy.s.sol" \
    --rpc-url $RPC_NODE_URL \
    --sender $SENDER_ADDRESS \
    --keystores $KEYSTORE_PATH \
    --slow \
    --broadcast \
    -vvvv
