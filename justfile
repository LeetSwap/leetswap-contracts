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

run-forge-script name func="run()" *args="":
    #!/bin/sh

    echo "Running script {{name}}"
    echo "Func: {{func}}"
    echo "Args: {{args}}"

    forge script "script/{{name}}.s.sol" \
    --rpc-url $RPC_NODE_URL \
    --sender $SENDER_ADDRESS \
    --keystores $KEYSTORE_PATH \
    --sig "{{func}}" \
    --slow \
    --broadcast \
    -vvvv {{args}}

deploy-dex-v2:
    #!/bin/sh

    just run-forge-script DeployDEXV2

deploy-leet-token router:
    #!/bin/sh

    just run-forge-script DeployLeetToken "run(address)" {{router}}

launch-leet-token router noteLiquidityAmount launchTimestamp:
    #!/bin/sh

    just run-forge-script DeployLeetToken "deployAndLaunch(address,uint256,uint256)" {{router}} {{noteLiquidityAmount}} {{launchTimestamp}}

leet-token-add-pair leet pair:
    #!/bin/sh

    just run-forge-script ManageLeetToken "addPair(address,address)" {{leet}} {{pair}}

deploy-leetchef-v1 leet:
    #!/bin/sh

    just run-forge-script DeployLeetChefV1 "run(address)" {{leet}}

leetchef-v1-add-lp-token leetchef lp-token alloc-points:
    #!/bin/sh

    just run-forge-script ManageLeetChefV1 "addLPToken(address,address,uint256)" {{leetchef}} {{lp-token}} {{alloc-points}}

leetchef-v1-set-emissions-per-second leetchef emissions:
    #!/bin/sh

    just run-forge-script ManageLeetChefV1 "setEmissionsPerSecond(address,uint256)" {{leetchef}} {{emissions}}

deploy-leetbar leet:
    #!/bin/sh

    just run-forge-script DeployLeetBar "run(address)" {{leet}}

leetbar-enter leetbar amount:
    #!/bin/sh

    just run-forge-script ManageLeetBar "enter(address,uint256)" {{leetbar}} {{amount}}

turnstile-withdraw turnstile-address token-id:
    #!/bin/sh

    just run-forge-script ManageTurnstile "withdraw(address,uint256)" {{turnstile-address}} {{token-id}}
