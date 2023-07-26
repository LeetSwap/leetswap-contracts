// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

import {IRewarder} from "./interfaces/IRewarder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface ILeetChef {
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. SUSHI to distribute per block.
        uint256 lastRewardBlock; // Last block number that SUSHI distribution occurs.
        uint256 accSushiPerShare; // Accumulated SUSHI per share, times 1e12. See below.
    }

    function poolInfo(
        uint256 pid
    ) external view returns (ILeetChef.PoolInfo memory);

    function totalAllocPoint() external view returns (uint256);

    function deposit(uint256 _pid, uint256 _amount) external;

    function lpToken(uint256) external view returns (IERC20);
}

contract TimeLimitedRewarder is IRewarder, Ownable {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20 for IERC20;

    IERC20 public immutable rewardToken;
    address public immutable LEETCHEF_V1;
    uint256 public immutable startTime;
    uint256 public immutable duration;

    /// @notice Info of each LeetChef user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of REWARD_TOKEN entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 unpaidRewards;
    }

    /// @notice Info of each LeetChef pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of REWARD_TOKEN to distribute per block.
    struct PoolInfo {
        uint256 accRewardTokenPerShare;
        uint256 lastRewardTime;
        uint256 allocPoint;
    }

    /// @notice Info of each pool.
    mapping(uint256 => PoolInfo) public poolInfo;

    uint256[] public poolIds;

    /// @notice Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    uint256 public baseRewardPerSecond;
    uint256 private constant ACC_TOKEN_PRECISION = 1e12;

    uint256 internal unlocked;

    modifier lock() {
        require(unlocked == 1, "LOCKED");
        unlocked = 2;
        _;
        unlocked = 1;
    }

    event LogOnReward(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to
    );
    event LogPoolAddition(uint256 indexed pid, uint256 allocPoint);
    event LogSetPool(uint256 indexed pid, uint256 allocPoint);
    event LogUpdatePool(
        uint256 indexed pid,
        uint256 lastRewardTime,
        uint256 lpSupply,
        uint256 accRewardTokenPerShare
    );
    event LogBaseRewardPerSecond(uint256 baseRewardPerSecond);
    event LogInit();

    constructor(
        IERC20 _rewardToken,
        uint256 _totalRewardableSupply,
        address _LEETCHEF_V1,
        uint256 _duration
    ) {
        rewardToken = _rewardToken;
        LEETCHEF_V1 = _LEETCHEF_V1;
        startTime = block.timestamp;
        duration = _duration;
        baseRewardPerSecond = _totalRewardableSupply / _duration;
        unlocked = 1;
    }

    function onPrimaryTokenReward(
        uint256 pid,
        address _user,
        address to,
        uint256,
        uint256 lpToken
    ) external override onlyLeetChef lock {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][_user];
        uint256 pending;
        if (user.amount > 0) {
            pending = (user.amount.mul(pool.accRewardTokenPerShare) /
                ACC_TOKEN_PRECISION).sub(user.rewardDebt).add(
                    user.unpaidRewards
                );
            uint256 balance = rewardToken.balanceOf(address(this));
            if (pending > balance) {
                rewardToken.safeTransfer(to, balance);
                baseRewardPerSecond = 0;
            } else {
                rewardToken.safeTransfer(to, pending);
                user.unpaidRewards = 0;
            }
        }
        user.amount = lpToken;
        user.rewardDebt =
            lpToken.mul(pool.accRewardTokenPerShare) /
            ACC_TOKEN_PRECISION;
        emit LogOnReward(_user, pid, pending - user.unpaidRewards, to);
    }

    function pendingTokens(
        uint256 pid,
        address user,
        uint256
    )
        external
        view
        override
        returns (IERC20[] memory rewardTokens, uint256[] memory rewardAmounts)
    {
        IERC20[] memory _rewardTokens = new IERC20[](1);
        _rewardTokens[0] = (rewardToken);
        uint256[] memory _rewardAmounts = new uint256[](1);
        _rewardAmounts[0] = pendingToken(pid, user);
        return (_rewardTokens, _rewardAmounts);
    }

    /// @notice Sets the rewardToken per second to be distributed. Can only be called by the owner.
    /// @param _baseRewardPerSecond The amount of RewardToken to be distributed per second.
    function setBaseRewardPerSecond(
        uint256 _baseRewardPerSecond
    ) public onlyOwner {
        baseRewardPerSecond = _baseRewardPerSecond;
        emit LogBaseRewardPerSecond(_baseRewardPerSecond);
    }

    modifier onlyLeetChef() {
        require(
            msg.sender == LEETCHEF_V1,
            "Only LeetChef can call this function."
        );
        _;
    }

    /// @notice Returns the number of LeetChef pools.
    function poolLength() public view returns (uint256 pools) {
        pools = poolIds.length;
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param allocPoint AP of the new pool.
    /// @param _pid Pid on LeetChef
    function add(uint256 allocPoint, uint256 _pid) public onlyOwner {
        require(poolInfo[_pid].lastRewardTime == 0, "Pool already exists");
        uint256 lastRewardTime = _getBlockTimestamp();
        totalAllocPoint = totalAllocPoint.add(allocPoint);

        poolInfo[_pid] = PoolInfo({
            allocPoint: allocPoint,
            lastRewardTime: lastRewardTime,
            accRewardTokenPerShare: 0
        });
        poolIds.push(_pid);
        emit LogPoolAddition(_pid, allocPoint);
    }

    /// @notice Update the given pool's REWARD_TOKEN allocation point and `IRewarder` contract. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOwner {
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
        emit LogSetPool(_pid, _allocPoint);
    }

    /// @notice Allows owner to reclaim/withdraw any tokens (including reward tokens) held by this contract
    /// @param token Token to reclaim, use 0x00 for Ethereum
    /// @param amount Amount of tokens to reclaim
    /// @param to Receiver of the tokens, first of his name, rightful heir to the lost tokens,
    /// reightful owner of the extra tokens, and ether, protector of mistaken transfers, mother of token reclaimers,
    /// the Khaleesi of the Great Token Sea, the Unburnt, the Breaker of blockchains.
    function reclaimTokens(
        address token,
        uint256 amount,
        address payable to
    ) public onlyOwner {
        if (token == address(0)) {
            to.transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    /// @notice View function to see pending Token
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending REWARD_TOKEN reward for a given user.
    function pendingToken(
        uint256 _pid,
        address _user
    ) public view returns (uint256 pending) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardTokenPerShare = pool.accRewardTokenPerShare;
        uint256 lpSupply = ILeetChef(LEETCHEF_V1).lpToken(_pid).balanceOf(
            LEETCHEF_V1
        );
        if (_getBlockTimestamp() > pool.lastRewardTime && lpSupply != 0) {
            uint256 time = _getBlockTimestamp().sub(pool.lastRewardTime);
            uint256 rewardTokenReward = time.mul(baseRewardPerSecond).mul(
                pool.allocPoint
            ) / totalAllocPoint;
            accRewardTokenPerShare = accRewardTokenPerShare.add(
                rewardTokenReward.mul(ACC_TOKEN_PRECISION) / lpSupply
            );
        }
        pending = (user.amount.mul(accRewardTokenPerShare) /
            ACC_TOKEN_PRECISION).sub(user.rewardDebt).add(user.unpaidRewards);
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    /// @param pids Pool IDs of all to be updated. Make sure to update all active pools.
    function massUpdatePools(uint256[] calldata pids) external {
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(pids[i]);
        }
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
        if (_getBlockTimestamp() > pool.lastRewardTime) {
            uint256 lpSupply = ILeetChef(LEETCHEF_V1).lpToken(pid).balanceOf(
                LEETCHEF_V1
            );

            if (lpSupply > 0) {
                uint256 time = _getBlockTimestamp().sub(pool.lastRewardTime);
                uint256 rewardTokenReward = time.mul(baseRewardPerSecond).mul(
                    pool.allocPoint
                ) / totalAllocPoint;
                pool.accRewardTokenPerShare = pool.accRewardTokenPerShare.add(
                    (rewardTokenReward.mul(ACC_TOKEN_PRECISION) / lpSupply)
                );
            }
            pool.lastRewardTime = _getBlockTimestamp();
            poolInfo[pid] = pool;
            emit LogUpdatePool(
                pid,
                pool.lastRewardTime,
                lpSupply,
                pool.accRewardTokenPerShare
            );
        }
    }

    function _getBlockTimestamp() internal view returns (uint256) {
        uint256 endTime = startTime + duration;
        if (block.timestamp > endTime) {
            return endTime;
        } else if (block.timestamp < startTime) {
            return startTime;
        } else {
            return block.timestamp;
        }
    }

    function rewardPerSecond() public view returns (uint256) {
        if (block.timestamp < startTime) {
            return 0;
        } else if (block.timestamp > startTime + duration) {
            return 0;
        } else {
            return baseRewardPerSecond;
        }
    }
}
