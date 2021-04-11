pragma solidity ^0.8.0;
import "../token/ERC20/IERC20.sol";
import "../token/ProperlyToken.sol";
import "../access/Ownable.sol";
import "../utils/math/SafeMath.sol";
import "../token/ERC20/libs/SafeERC20.sol";

// Code is inspired from most popular farms on BSC.
// Code has been modified.

contract Farm is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // The Protocol Token!
    ProperlyToken public dpi;
    // Dev address.
    address public devaddr;
    // DPI tokens created per block.
    uint256 public dpiPerBlock;
    // Deposit Fee address
    address public feeAddress;

    constructor(
        ProperlyToken _dpi,
        address _devaddr,
        address _feeAddress,
        uint256 _dpiPerBlock,
        uint256 _startBlock
    ) public {
        dpi = _dpi;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        dpiPerBlock = _dpiPerBlock;
        startBlock = _startBlock;
    }

    struct UserInfo {
        uint256 amount; // How many LP tokens the user has user provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //      pending reward = (user.amount * pool.accdpiPerShare) - user.rewardDebt

        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accdpiPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // Portion of reward allocation to this pool.
        uint256 lastRewardBlock; // Block number when last distribution happened on a pool.
        uint256 accDPIPerShare; // Accumulated DPI's per share, times 1e12. See below.
        uint16 depositFeeBP; // Deposit fee in basis points
    }

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when DPI mining starts.
    uint256 public startBlock;

    // Calculate how many pools exist.
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(ERC20 => bool) public poolExistence;
    // Prevents creation of a pool with the same token.
    modifier nonDuplicated(ERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Create a new pool. Can only be called by the owner.
    // You define the token address.
    // You set the weightto the pool - allocPoint. It determine how much rewards will go to stakers of this pool relative to other pools.
    // You also define the deposit fee. This fee is moved to fee collecter address.
    function add(
        uint256 _allocPoint,
        ERC20 _lpToken,
        uint16 _depositFeeBP,
        bool _withUpdate
    ) public onlyOwner nonDuplicated(_lpToken) {
        // The deposit fee has to be below 100%
        require(
            _depositFeeBP <= 10000,
            "add: invalid deposit fee basis points"
        );
        if (_withUpdate) {
            massUpdatePools();
        }

        // In case Farm already running set the lastRewardBlock to curenct block number.
        // In case farm is launched in the future, set it to the farm startBlock number.
        uint256 lastRewardBlock =
            block.number > startBlock ? block.number : startBlock;
        // Adjust totalAllocPoint to weight of all pools, accounting for new pool added.
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        // You set the pool as it already exists so you wouln't be able to create the same exact pool twice.
        poolExistence[_lpToken] = true;
        // Store the information of the new pool.
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accDPIPerShare: 0,
                depositFeeBP: _depositFeeBP
            })
        );
    }

    // Update reward variables for all pools.
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // View pending DPIs rewards.
    function pendingDPI(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accDPIPerShare = pool.accDPIPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 blockDifference = block.number.sub(pool.lastRewardBlock);
            uint256 dpiReward =
                blockDifference.mul(dpiPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accDPIPerShare = accDPIPerShare.add(
                dpiReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accDPIPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        // if the pool reward block number is in the future the farm has not started yet.
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        // Total of pool token that been supplied.
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        // If pool has no LP tokens or pool weight is set to 0 don't distribute rewards.
        // Just update the update to last block.
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        // If none of the above is true mint tokens and distribute rewards.
        // First we get the number of blocks that we have advanced forward since the last time we updated the farm.
        uint256 blockDifference = block.number.sub(pool.lastRewardBlock);
        //  After we got to the block timeframe defference, we calculate how much we mint.
        // For each farm we consider the weight it has compared to the other farms.
        uint256 dpiReward =
            blockDifference.mul(dpiPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );

        // A % of reward is going to the developers address so that would be a portion of total reward.
        dpi.mint(devaddr, dpiReward.div(10));
        // We are minting to the protocol address the address the reward tokens.
        dpi.mint(address(this), dpiReward);

        //  Calculates how many tokens does each supplied of token get.
        pool.accDPIPerShare = pool.accDPIPerShare.add(
            dpiReward.mul(1e12).div(lpSupply)
        );
        // We update the farm to the current block number.
        pool.lastRewardBlock = block.number;
    }

    // Deposit pool tokens for DPI allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        // Update pool when user interacts with the contract.
        updatePool(_pid);

        // If the user has previously deposited money to the farm.
        if (user.amount > 0) {
            // Calculate how much does the farm owe the user.
            uint256 pending =
                user.amount.mul(pool.accDPIPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            // When user executes deposit, pending rewards get sent to the user.
            if (pending > 0) {
                safeDPITransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            // If the pool has a deposit fee
            if (pool.depositFeeBP > 0) {
                // Calculate what does it represent in token terms.
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                // Send the deposit fee to the feeAddress
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                // Add the user token to the farm and substract the deposit fee.
                user.amount = user.amount.add(_amount).sub(depositFee);
                // If there is no deposit fee just add the money to the total amount that a user has deposited.
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        // Generate Debt for the previous rewards that the user is not entitled to. Because he just entered.
        user.rewardDebt = user.amount.mul(pool.accDPIPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw pool tokens,
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        // Check's what is the pending amount considering current block.
        // Assuming that we distribute 5 Tokens for every 1 token.
        //  if user deposited 0.5 tokens, he recives 2.5 tokens.
        uint256 pending =
            user.amount.mul(pool.accDPIPerShare).div(1e12).sub(user.rewardDebt);
        // If the user has a reward pending, send the user his rewards.
        if (pending > 0) {
            safeDPITransfer(msg.sender, pending);
        }
        // If the user is withdrawing from the farm more than 0 tokens
        if (_amount > 0) {
            // reduce from the user DB the ammount he is trying to withdraw.
            user.amount = user.amount.sub(_amount);
            // Send  the user the amount of LP tokens he is withdrawing.
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }

        user.rewardDebt = user.amount.mul(pool.accDPIPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // In case if rounding error causes pool to not have enough DPI TOKENS
    function safeDPITransfer(address _to, uint256 _amount) internal {
        // Check how many DPI token's on the protocol address.
        uint256 DPIBal = dpi.balanceOf(address(this));
        // In case if the amount requested is higher than the money on the protocol balance.
        if (_amount > DPIBal) {
            // Transfer absolutely everything from the balance to the contract.
            dpi.transfer(_to, DPIBal);
        } else {
            // If there is enough tokens on the protocol, make the usual transfer.
            dpi.transfer(_to, _amount);
        }
    }

    // Update developer fee address.
    function dev(address _devaddr) public {
        // Can be done only by developer
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    // Address that collects fees on the protocol.
    // Fees will be used to buy back DPI tokens.
    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
    }

    // Function that sets the new amount of how many new DPI Tokens will be minted per each block.
    function updateEmissionRate(uint256 _DPIPerBlock) public onlyOwner {
        massUpdatePools();
        dpiPerBlock = _DPIPerBlock;
    }
}
