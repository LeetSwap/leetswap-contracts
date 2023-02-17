// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

import {IRewarder} from "./interfaces/IRewarder.sol";
import {ILeetSwapV2Pair} from "@leetswap/dex/v2/interfaces/ILeetSwapV2Pair.sol";
import {ITurnstile} from "@leetswap/interfaces/ITurnstile.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface IMigratorChef {
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    function migrate(IERC20 token) external returns (IERC20);
}

interface ICSRContract {
    function turnstile() external view returns (ITurnstile);
}

contract LeetChefV1 is Ownable {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20 for IERC20;

    /// @notice Info of each LeetChefV1 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of PRIMARY_TOKEN entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    /// @notice Info of each LeetChefV1 pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of PRIMARY_TOKEN to distribute per block.
    struct PoolInfo {
        uint256 accPrimaryTokenPerShare;
        uint256 lastRewardTime;
        uint256 allocPoint;
    }

    /// @notice Address of PRIMARY_TOKEN contract.
    IERC20 public immutable PRIMARY_TOKEN;
    IMigratorChef public migrator;

    /// @notice Info of each LeetChefV1 pool.
    PoolInfo[] public poolInfo;
    /// @notice Address of the LP token for each LeetChefV1 pool.
    IERC20[] public lpToken;
    /// @notice Address of each `IRewarder` contract in LeetChefV1.
    IRewarder[] public rewarder;

    /// @notice Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    /// @dev Tokens added
    mapping(address => bool) public addedTokens;

    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    uint256 public primaryTokenPerSecond;
    uint256 private constant ACC_PRIMARY_TOKEN_PRECISION = 1e12;

    event Deposit(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to
    );
    event Withdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to
    );
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to
    );
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event LogPoolAddition(
        uint256 indexed pid,
        uint256 allocPoint,
        IERC20 indexed lpToken,
        IRewarder indexed rewarder
    );
    event LogSetPool(
        uint256 indexed pid,
        uint256 allocPoint,
        IRewarder indexed rewarder,
        bool overwrite
    );
    event LogUpdatePool(
        uint256 indexed pid,
        uint256 lastRewardTime,
        uint256 lpSupply,
        uint256 accPrimaryTokenPerShare
    );
    event LogPrimaryTokenPerSecond(uint256 primaryTokenPerSecond);

    error MigratorNotSet();
    error TokenAlreadyAdded();
    error MigratedBalanceUnmatch();
    error ReclaimingRewardToken();

    /// @param _primaryToken The PRIMARY_TOKEN token contract address.
    constructor(IERC20 _primaryToken) {
        PRIMARY_TOKEN = _primaryToken;

        ITurnstile turnstile = ICSRContract(address(_primaryToken)).turnstile();
        uint256 csrTokenID = turnstile.getTokenId(address(_primaryToken));
        turnstile.assign(csrTokenID);
    }

    /// @notice Returns the number of LeetChefV1 pools.
    function poolLength() public view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param allocPoint AP of the new pool.
    /// @param _lpToken Address of the LP ERC-20 token.
    /// @param _rewarder Address of the rewarder delegate.
    function add(
        uint256 allocPoint,
        IERC20 _lpToken,
        IRewarder _rewarder
    ) public onlyOwner {
        if (addedTokens[address(_lpToken)] == true) {
            revert TokenAlreadyAdded();
        }

        totalAllocPoint = totalAllocPoint.add(allocPoint);
        lpToken.push(_lpToken);
        rewarder.push(_rewarder);

        poolInfo.push(
            PoolInfo({
                allocPoint: allocPoint,
                lastRewardTime: block.timestamp,
                accPrimaryTokenPerShare: 0
            })
        );
        addedTokens[address(_lpToken)] = true;
        emit LogPoolAddition(
            lpToken.length.sub(1),
            allocPoint,
            _lpToken,
            _rewarder
        );
    }

    /// @notice Update the given pool's PRIMARY_TOKEN allocation point and `IRewarder` contract. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    /// @param _rewarder Address of the rewarder delegate.
    /// @param overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        IRewarder _rewarder,
        bool overwrite,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
        if (overwrite) {
            rewarder[_pid] = _rewarder;
        }
        emit LogSetPool(
            _pid,
            _allocPoint,
            overwrite ? _rewarder : rewarder[_pid],
            overwrite
        );
    }

    /// @notice Sets the primaryToken per second to be distributed. Can only be called by the owner.
    /// @param _primaryTokenPerSecond The amount of PrimaryToken to be distributed per second.
    /// @param _withUpdate True if all pools should be updated prior to setting the new primaryTokenPerSecond.
    function setPrimaryTokenPerSecond(
        uint256 _primaryTokenPerSecond,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        primaryTokenPerSecond = _primaryTokenPerSecond;
        emit LogPrimaryTokenPerSecond(_primaryTokenPerSecond);
    }

    /// @notice Set the `migrator` contract. Can only be called by the owner.
    /// @param _migrator The contract address to set.
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    /// @notice Migrate LP token to another LP contract through the `migrator` contract.
    /// @param _pid The index of the pool. See `poolInfo`.
    function migrate(uint256 _pid) public {
        if (address(migrator) == address(0)) {
            revert MigratorNotSet();
        }

        IERC20 _lpToken = lpToken[_pid];
        uint256 bal = _lpToken.balanceOf(address(this));
        _lpToken.approve(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(_lpToken);
        if (bal != newLpToken.balanceOf(address(this))) {
            revert MigratedBalanceUnmatch();
        }
        if (addedTokens[address(newLpToken)] == true) {
            revert TokenAlreadyAdded();
        }
        addedTokens[address(newLpToken)] = true;
        addedTokens[address(_lpToken)] = false;
        lpToken[_pid] = newLpToken;
    }

    /// @notice View function to see pending PRIMARY_TOKEN on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending PRIMARY_TOKEN reward for a given user.
    function pendingPrimaryToken(uint256 _pid, address _user)
        external
        view
        returns (uint256 pending)
    {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPrimaryTokenPerShare = pool.accPrimaryTokenPerShare;
        uint256 lpSupply = lpToken[_pid].balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 time = block.timestamp.sub(pool.lastRewardTime);
            uint256 primaryTokenReward = time.mul(primaryTokenPerSecond).mul(
                pool.allocPoint
            ) / totalAllocPoint;
            accPrimaryTokenPerShare = accPrimaryTokenPerShare.add(
                primaryTokenReward.mul(ACC_PRIMARY_TOKEN_PRECISION) / lpSupply
            );
        }
        pending = int256(
            user.amount.mul(accPrimaryTokenPerShare) /
                ACC_PRIMARY_TOKEN_PRECISION
        ).sub(user.rewardDebt).toUint256();
    }

    /// @notice Update reward variables for multiple pools. Be careful of gas spending!
    /// @param pids Pool IDs of all to be updated. Make sure to update all active pools.
    function massUpdatePools(uint256[] calldata pids) external {
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(pids[i]);
        }
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 len = poolInfo.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(i);
        }
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
        if (block.timestamp > pool.lastRewardTime) {
            uint256 lpSupply = lpToken[pid].balanceOf(address(this));
            if (lpSupply > 0) {
                uint256 time = block.timestamp.sub(pool.lastRewardTime);
                uint256 primaryTokenReward = time
                    .mul(primaryTokenPerSecond)
                    .mul(pool.allocPoint) / totalAllocPoint;
                pool.accPrimaryTokenPerShare = pool.accPrimaryTokenPerShare.add(
                    (primaryTokenReward.mul(ACC_PRIMARY_TOKEN_PRECISION) /
                        lpSupply)
                );
            }
            pool.lastRewardTime = block.timestamp;
            poolInfo[pid] = pool;
            emit LogUpdatePool(
                pid,
                pool.lastRewardTime,
                lpSupply,
                pool.accPrimaryTokenPerShare
            );
        }
    }

    /// @notice Deposit LP tokens to LeetChefV1 for PRIMARY_TOKEN allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(
        uint256 pid,
        uint256 amount,
        address to
    ) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][to];

        user.amount = user.amount.add(amount);
        user.rewardDebt = user.rewardDebt.add(
            int256(
                amount.mul(pool.accPrimaryTokenPerShare) /
                    ACC_PRIMARY_TOKEN_PRECISION
            )
        );

        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onPrimaryTokenReward(pid, to, to, 0, user.amount);
        }

        lpToken[pid].safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, pid, amount, to);
    }

    /// @notice Withdraw LP tokens from LeetChefV1.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdraw(
        uint256 pid,
        uint256 amount,
        address to
    ) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];

        user.rewardDebt = user.rewardDebt.sub(
            int256(
                amount.mul(pool.accPrimaryTokenPerShare) /
                    ACC_PRIMARY_TOKEN_PRECISION
            )
        );
        user.amount = user.amount.sub(amount);

        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onPrimaryTokenReward(pid, msg.sender, to, 0, user.amount);
        }

        lpToken[pid].safeTransfer(to, amount);

        emit Withdraw(msg.sender, pid, amount, to);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of PRIMARY_TOKEN rewards.
    function harvest(uint256 pid, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];
        int256 accumulatedPrimaryToken = int256(
            user.amount.mul(pool.accPrimaryTokenPerShare) /
                ACC_PRIMARY_TOKEN_PRECISION
        );
        uint256 _pendingPrimaryToken = accumulatedPrimaryToken
            .sub(user.rewardDebt)
            .toUint256();

        user.rewardDebt = accumulatedPrimaryToken;

        if (_pendingPrimaryToken != 0) {
            PRIMARY_TOKEN.safeTransfer(to, _pendingPrimaryToken);
        }

        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onPrimaryTokenReward(
                pid,
                msg.sender,
                to,
                _pendingPrimaryToken,
                user.amount
            );
        }

        emit Harvest(msg.sender, pid, _pendingPrimaryToken);
    }

    /// @notice Withdraw LP tokens from LeetChefV1 and harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens and PRIMARY_TOKEN rewards.
    function withdrawAndHarvest(
        uint256 pid,
        uint256 amount,
        address to
    ) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];
        int256 accumulatedPrimaryToken = int256(
            user.amount.mul(pool.accPrimaryTokenPerShare) /
                ACC_PRIMARY_TOKEN_PRECISION
        );
        uint256 _pendingPrimaryToken = accumulatedPrimaryToken
            .sub(user.rewardDebt)
            .toUint256();

        user.rewardDebt = accumulatedPrimaryToken.sub(
            int256(
                amount.mul(pool.accPrimaryTokenPerShare) /
                    ACC_PRIMARY_TOKEN_PRECISION
            )
        );
        user.amount = user.amount.sub(amount);

        PRIMARY_TOKEN.safeTransfer(to, _pendingPrimaryToken);

        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onPrimaryTokenReward(
                pid,
                msg.sender,
                to,
                _pendingPrimaryToken,
                user.amount
            );
        }

        lpToken[pid].safeTransfer(to, amount);

        emit Withdraw(msg.sender, pid, amount, to);
        emit Harvest(msg.sender, pid, _pendingPrimaryToken);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Recipient of the LP tokens.
    function emergencyWithdraw(uint256 pid, address to) public {
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onPrimaryTokenReward(pid, msg.sender, to, 0, 0);
        }

        // Note: transfer can fail or succeed if `amount` is zero.
        lpToken[pid].safeTransfer(to, amount);
        emit EmergencyWithdraw(msg.sender, pid, amount, to);
    }

    /// @notice Allows owner to reclaim/withdraw stuck tokens (except reward tokens) held by this contract.
    /// @param token Token to reclaim, use address(0) for Ether.
    /// @param amount Amount of tokens to reclaim.
    /// @param to Recipient of the tokens.
    function reclaimTokens(
        address token,
        uint256 amount,
        address payable to
    ) public onlyOwner {
        if (addedTokens[token]) {
            revert ReclaimingRewardToken();
        }

        if (token == address(0)) {
            to.transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    /// @notice Allows owner to reclaim/withdraw the primary token held by this contract for migration.
    /// @param amount Amount of tokens to reclaim.
    function reclaimPrimaryToken(uint256 amount) public onlyOwner {
        PRIMARY_TOKEN.safeTransfer(owner(), amount);
    }

    /// @notice Allows owner to claim fees for Solidly-based LP tokens.
    /// @param pid The index of the pool. See `poolInfo`.
    function claimLPFees(uint256 pid) public onlyOwner {
        ILeetSwapV2Pair pair = ILeetSwapV2Pair(address(lpToken[pid]));
        IERC20 token0 = IERC20(pair.token0());
        IERC20 token1 = IERC20(pair.token1());

        uint256 initialBalance0 = token0.balanceOf(address(this));
        uint256 initialBalance1 = token1.balanceOf(address(this));
        pair.claimFees();

        uint256 token0Fees = token0.balanceOf(address(this)).sub(
            initialBalance0
        );
        uint256 token1Fees = token1.balanceOf(address(this)).sub(
            initialBalance1
        );
        token0.safeTransfer(owner(), token0Fees);
        token1.safeTransfer(owner(), token1Fees);
    }

    /// @notice Iterate over all pools and call `claimLPFees` for each.
    function claimAllLPFees() public onlyOwner {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            claimLPFees(pid);
        }
    }
}
