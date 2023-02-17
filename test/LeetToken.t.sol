// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import "@leetswap/dex/v2/LeetSwapV2Router01.sol";
import "@leetswap/dex/v2/LeetSwapV2Factory.sol";
import "@leetswap/dex/v2/LeetSwapV2Pair.sol";
import "@leetswap/interfaces/IWCANTO.sol";
import "@leetswap/dex/native/interfaces/IBaseV1Factory.sol";
import "@leetswap/dex/native/interfaces/IBaseV1Router01.sol";
import "../script/DeployDEXV2.s.sol";
import "../script/DeployLeetToken.s.sol";

import {MockERC20LiquidityManageable} from "./doubles/MockERC20LiquidityManageable.sol";
import {MockERC20Tax} from "./doubles/MockERC20Tax.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract TestLeetToken is Test {
    uint256 mainnetFork;

    DeployDEXV2 public dexDeployer;
    LeetSwapV2Factory public factory;
    LeetSwapV2Router01 public router;

    IBaseV1Factory public cantoDEXFactory;
    IBaseV1Router01 public cantoDEXRouter;

    IWCANTO public weth;
    MockERC20 public token0;
    MockERC20 public token1;
    MockERC20Tax public token0Tax;
    MockERC20LiquidityManageable public token0LM;

    uint256 public taxRate;
    uint256 public taxDivisor;
    address public taxRecipient;

    function setUp() public {
        mainnetFork = vm.createSelectFork(
            "https://canto.slingshot.finance",
            2923489
        );

        dexDeployer = new DeployDEXV2();
        (factory, router) = dexDeployer.run();
        weth = IWCANTO(router.WETH());

        cantoDEXFactory = IBaseV1Factory(dexDeployer.cantoDEXFactory());

        token0 = new MockERC20("Token0", "T0", 18);
        token1 = new MockERC20("Token1", "T1", 18);
        token0.mint(address(this), 10 ether);
        token1.mint(address(this), 10 ether);

        taxRate = 1000;
        taxDivisor = 1e4;
        taxRecipient = address(0xDEADBEEF);

        token0Tax = new MockERC20Tax(
            "Token0Tax",
            "T0T",
            18,
            taxRate,
            taxDivisor,
            taxRecipient
        );
        token0Tax.mint(address(this), 10 ether);

        token0LM = new MockERC20LiquidityManageable(
            "Token0LM",
            "T0LM",
            18,
            taxRate,
            taxDivisor,
            taxRecipient
        );
        token0LM.mint(address(this), 10 ether);

        token0Tax.setPair(
            address(router.pairFor(address(token0Tax), address(weth))),
            true
        );
        token0Tax.setPair(
            address(router.pairFor(address(token0Tax), address(token0))),
            true
        );
        token0Tax.setPair(
            address(router.pairFor(address(token0Tax), address(token1))),
            true
        );
        token0Tax.setPair(
            address(router.pairFor(address(token0Tax), address(token0LM))),
            true
        );

        token0LM.setPair(
            address(router.pairFor(address(token0LM), address(weth))),
            true
        );
        token0LM.setPair(
            address(router.pairFor(address(token0LM), address(token0))),
            true
        );
        token0LM.setPair(
            address(router.pairFor(address(token0LM), address(token1))),
            true
        );

        vm.label(address(dexDeployer), "dexDeployer");
        vm.label(address(factory), "factory");
        vm.label(address(router), "router");
        vm.label(address(weth), "wcanto");
        vm.label(address(token0), "token0");
        vm.label(address(token1), "token1");
        vm.label(address(token0Tax), "token0Tax");
        vm.label(address(token0LM), "token0LM");
        vm.label(address(cantoDEXFactory), "cantoDEXFactory");

        vm.deal(address(this), 100 ether);
        weth.deposit{value: 10 ether}();
    }

    function testLeetTokenDeployment() public {
        DeployLeetToken deployer = new DeployLeetToken();
        deployer.run(address(router));
    }

    receive() external payable {}
}
