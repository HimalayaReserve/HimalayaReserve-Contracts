
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./HimalayaToken.sol";
import "./HimalayaDollarToken.sol";

// HimalayaReserve 2.0: MasterChefV2 Security Enhanced

//Himalaya Reserve 2.0 is a secret experimental decentralized system governed by decentralized autonomous organization(DAO), while the centralized Himalaya Reserve 1.0 is launched on November 1st, 2021. It has world's first duel coin design including HCN(Himalaya Coin) and HDO(Himalaya Dollar). Every HDO is 1:1 pegged on US Dollar and 100% of its circulalation will be bought back by the Himalaya Reserve Foundation one year after deployment. Every HCN is 1:1,000 hard pegged on HDO during first year and every HCN circulated on Binance Chain worths at least $1,000.

// HCN >= $1,000
// HDO == $1

// Completely removed the trust of the owner.
//
// 1.Removed migrator() function
//
// 2.All configuration functions are 720-hour timelocked

// 3.How to check whether all governance functions are locked or not: 

// Call TIMELOCK() with fucntion id, eg: "1", to check if "add()" is locked. If the returned value is 0, it is locked. If the returned value is not 0, it would be the timestamp 72 hours after calling the unlock() tx. And when the current timestamp is larger than the returned timestamp, the owner can call the unlocked functions.

// Below is the id list of all governance functions that can be unlocked/locked. By default, all functions are locked and all returned values of the functions available for the owner are 0.

//    0    :   airdropByOwner()
//    1    :   add()
//    2    :   addList()
//    3    :   setToken()
//    4    :   set()
//    5    :   setList()
//    6    :   updateMultiplier()
//    7    :   updateEmissionRate()
//    8    :   upgrade()

// 4.How to unlock one specific function:
//    Owner calls unlock() function with a specific function id, eg: owner unlocks "upgrade()" through calling "unlock()" with "8" as its parameter. And the community can check the lock/unlock status via calling TIMELOCK() with "8" as parameter.

// 5.Restrictions of using unlocked functions:

    // a. Every time the owner calls the unlocked function, it would be 720-hour locked again automatically. It means the owner can not regularly change the underlying protocol.

    // b.Owner can NOT change _allocation point into an infinite number
    // require (_allocPoint <= 200 && _depositFeeBP <= 500, 'add: invalid allocpoints or deposit fee basis points');

    // c.Owner can NOT set deposit fee higher than 5%
    // uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
    // require (_allocPoint <= 5000 && _depositFeeBP <= 500, 'set: invalid allocpoints or deposit fee basis points');

    // d.Owner can NOT set multiplier higher than 5
    // require(multiplierNumber <= 5, 'multipler too high');

    // e.Owner can NOT set emission rate higher than the initial himalaya per block
    // require(_himalayaPerBlock <= 1000000000000000000, 'must be smaller than the initial emission rate');

    // f.upgrade() function should NOT be unlocked unless it is really necessary to upgrade the protocol. The returned value of calling TIMELOCK() with parameter "8" should ALWAYS be 0.

    // g.In fact, to achieve maximum security, all returned values for calling TIMELOCK() with parameters from 0 to 8 should be 0, which means all governance functions are perfectly locked.

// 6.ReentrancyGuard for deposit(), withdraw(), emergencyWithdraw()

//

contract MasterChefV2 is Ownable, ReentrancyGuard, Initializable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of BEP20s
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accBep20PerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accBep20PerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. BEP20s to distribute per block.
        uint256 lastRewardBlock;  // Last block number that BEP20s distribution occurs.
        uint256 accBep20PerShare;   // Accumulated BEP20s per share, times 1e12. See below.
        uint256 depositFeeBP;      // Deposit fee in basis points
    }

    // The BEP20 TOKEN!
    BEP20 public bep20;
    // The BEP20 TOKEN!
    BEP20 public bep20stake;
    // Dev address.
    address public devaddr;
    // BEP20 tokens created per block.
    uint256 public bep20PerBlock;
    // Bonus muliplier for early bep20 makers.
    uint256 public bonusMultiplier;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // User list
    address[] public userList;
    // Only deposit user can get airdrop.
    mapping(address => bool) public userIsIn;
    uint256 public userInLength;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when BEP20 mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 goosePerBlock);

    //// Timelock Configuration
    enum Functions { AIRDROPBYOWNER, ADD, ADDLIST, SETTOKEN, SET, SETLIST, UPDATEMULTIPLIER, UPDATEEMISSIONRATE, UPGRADE }    
    // 720 hours timelock
    uint256 private constant _TIMELOCK = 30 days;
    mapping(Functions => uint256) public TIMELOCK;
    mapping(IBEP20 => bool) public poolExistence;
    modifier nonDuplicated(IBEP20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    modifier notLocked(Functions _fn) {
        require(
            TIMELOCK[_fn] != 0 && // The returned value "0" of "TIMELOCK[_fn]" means the function is locked.
            TIMELOCK[_fn] <= block.timestamp, // If the returned value of "TIMELOCK[_fn]" is larger than the current block timestamp, it means the function is still locked and pending to be unlocked until the returned value is smaller than the growing block timestamp.
        "Function is timelocked");
        _;
    }

    constructor() public {
    }

    // This function CAN NOT be called once initialized
    function init(
        uint256 _startBlock,
        uint256 _bep20PerBlock,
        uint256 _bonusMultiplier,
        BEP20 _bep20,
        BEP20 _bep20stake,
        address _devaddr,
        address _feeAddress,
        address[] memory _poolTokens,
        uint256[] memory _poolAlloc
    ) public initializer {
        // CAN NOT be called once initialized)
        require(startBlock == 0 && bep20PerBlock == 0, "Initialization done");

        startBlock = _startBlock; //
        bep20PerBlock = _bep20PerBlock; //bep20PerBlock = 100000000000000000; 1e18
        bonusMultiplier = _bonusMultiplier; //bonusMultiplier = 1

        bep20 = _bep20;
        bep20stake = _bep20stake;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        
        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _bep20,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accBep20PerShare: 0,
            depositFeeBP : 0
        }));
        totalAllocPoint = 1000;
        poolExistence[IBEP20(_bep20)] = true;

        uint256 i;
        for (i = 0; i < _poolTokens.length; ++i) {
            poolInfo.push(PoolInfo({
                lpToken: IBEP20(_poolTokens[i]),
                allocPoint: 100,
                lastRewardBlock: startBlock,
                accBep20PerShare: 0,
                depositFeeBP : 100
            }));
            poolExistence[IBEP20(_poolTokens[i])] = true;
		}

        uint256 j;
        for (j = 0; j < _poolAlloc.length; ++j) {
            poolInfo[j+1].allocPoint = _poolAlloc[j];
		}

        updateStakingPool();
    }

    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function updateStakingPool() public {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = points.mul(4);
            poolInfo[0].allocPoint = points;
        }
    }

    // Internal function which is called when users deposit and withdraw
    function _userIn(address _user) internal {
        // a dummy amount to check if _user has deposited any tokens into the farm
        uint256 dummy = 0;
        for (uint256 pid = 0; pid < poolLength(); ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            UserInfo storage user = userInfo[pid][_user];
            if (user.amount == 0 || pool.allocPoint == 0) {
                continue;
            }
            dummy = dummy.add(user.amount);
        }
        if(dummy != 0) {
            userIsIn[_user] = true;
        } else {
            userIsIn[_user] = false;
        }
        userInLength = 0;
        for (uint256 i = 0; i < userList.length; i++) {
            if (userIsIn[userList[i]] = true) {
                userInLength = userInLength.add(1);
            }
        }
    }

    // Anyone can call airdrop to send any tokens as airdrop to available users in the userList array
    function airdrop(IBEP20 _token, uint256 _totalAmount) public {
        require(IBEP20(_token).balanceOf(msg.sender) >= _totalAmount);
        uint256 amountPerUser = _totalAmount.div(userInLength);
        for (uint256 i = 0; i < userList.length; i++) {
            if (userIsIn[userList[i]] == true) {
                IBEP20(_token).safeTransfer(userList[i], amountPerUser);
            }
        }
    }

    // 720-hour TimeLocked
    // This function is timelocked and airdropByOwner() can only be called every 720 hours
    // Owner can send any tokens or mint BEP20 tokens as airdrop to available users in the userList array
    // However there's limitations to the frequency and maximum amount of BEP20 tokens can be airdropped
    // Owner can NOT airdrop more than 1% of the current BEP20 totalSupply every 720 hours
    function airdropByOwner(IBEP20 _token, uint256 _value, bool _isMint) public onlyOwner notLocked(Functions.AIRDROPBYOWNER) {
        // if isMint == true, neglect _token parameter and mint BEP20 as airdrop
        if (_isMint == true) {
            for (uint256 i = 0; i < userList.length; i++) {
                if (userIsIn[userList[i]] == false) {
                    continue;
                }
                // Owner can not airdrop more than 1% of the current totalSupply every 720 hours
                require(_value.div(bep20.totalSupply()).mul(100) <= 1);
                bep20.mint(userList[i], _value.div(userInLength));
            }
        } else if (_isMint == false) {
            airdrop(_token, _value);
        }
        // Refresh TimeLock for airdropByOwner() and add 720 hours lock
        unlock(Functions.AIRDROPBYOWNER);
    }

    // Read Only
    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(bonusMultiplier);
    }

    // Can only be called by the owner
    // Should be monitored by everyone if there's any configuration
    // Unlock Timelock For Specified Function, it adds 30 days delay before it is possible to call the unlocked function.
    function unlock(Functions _fn) public onlyOwner {
        TIMELOCK[_fn] = block.timestamp + _TIMELOCK;
    }

    // Can only be called by the owner
    //Lock specific function immediately, makes it impossible to be called
    function timelock(Functions _fn) public onlyOwner {
        TIMELOCK[_fn] = 0;
    }

    // 720-hour TimeLocked
    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint256 _depositFeeBP, bool _withUpdate) public onlyOwner nonDuplicated(_lpToken) notLocked(Functions.ADD) {
        // RESTRICT ALLOCPOINT/DEPOSITFEE //
        require (_allocPoint <= 200 && _depositFeeBP <= 500, 'add: invalid allocpoints or deposit fee basis points');

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accBep20PerShare: 0,
            depositFeeBP : _depositFeeBP
        }));
        updateStakingPool();

        //TIMELOCK THIS FUNCTION AS SOON AS IT IS CALLED
        timelock(Functions.ADD);
    }

    // 720-hour TimeLocked
    // Add new tokens to the pool. Can only be called by the owner.
    function addList(address[] memory _lpToken, uint256 _allocPoint, uint256 _depositFeeBP) public onlyOwner notLocked(Functions.ADDLIST) {
        // RESTRICT ALLOCPOINT/DEPOSITFEE //
        require (_allocPoint <= 200 && _depositFeeBP <= 500, 'add: invalid allocpoints or deposit fee basis points');
        // RESTRICT ADDLIST LENGTH //
        require (_lpToken.length <= 50, 'Forbid Adding Infinite LPTokens');

        uint256 i;
        for (i = 0; i < _lpToken.length; ++i) {
            poolExistence[IBEP20(_lpToken[i])] = true;
            poolInfo.push(PoolInfo({
                lpToken: IBEP20(_lpToken[i]),
                allocPoint: _allocPoint,
                lastRewardBlock: startBlock,
                accBep20PerShare: 0,
                depositFeeBP : _depositFeeBP
            }));
            updateStakingPool();
		}

        //TIMELOCK THIS FUNCTION AS SOON AS IT IS CALLED
        timelock(Functions.ADDLIST);
    }

    // 720-hour TimeLocked
    // setToken, can only be called by the owner. Normally this function should NOT be unlocked.
    function setToken(uint _pid, IBEP20 _newToken) public onlyOwner notLocked(Functions.SETTOKEN) {

        PoolInfo storage pool = poolInfo[_pid];
        
        //CAN ONLY BE CALLED IF NO TOKEN IN THE POOL//
        require ( IBEP20(pool.lpToken).balanceOf(address(this)) != 0 && pool.lpToken != bep20stake);

        pool.lpToken = _newToken;

        //TIMELOCK THIS FUNCTION AS SOON AS IT IS CALLED
        timelock(Functions.SETTOKEN);
    }

    // 720-hour TimeLocked
    // Update the given pool's BEP20 allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint256 _depositFeeBP, bool _withUpdate) public onlyOwner notLocked(Functions.SET) {
        // RESTRICT ALLOCPOINT
        require (_allocPoint <= 5000 && _depositFeeBP <= 500, 'set: invalid allocpoints or deposit fee basis points');

        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            updateStakingPool();
        }
        poolInfo[_pid].depositFeeBP = _depositFeeBP;

        //TIMELOCK THIS FUNCTION AS SOON AS IT IS CALLED
        timelock(Functions.SET);
    }

    // 720-hour TimeLocked
    // Update the given pools' BEP20 allocation point. Can only be called by the owner.
    function setList(uint256[] memory _poolAlloc, uint256[] memory _depositFeeBP) public onlyOwner notLocked(Functions.SETLIST) {
        uint256 i;
        for (i = 0; i < _poolAlloc.length; ++i) {
        // RESTRICT ALLOCPOINT
            require (_poolAlloc[i] <= 200 && _depositFeeBP[i] <= 500, 'setList: invalid allocpoints or deposit fee basis points');
            poolInfo[i+1].allocPoint = _poolAlloc[i];
            totalAllocPoint = totalAllocPoint.sub(poolInfo[i+1].allocPoint).add(_poolAlloc[i]);
            uint256 prevAllocPoint = poolInfo[i+1].allocPoint;
            poolInfo[i+1].allocPoint = _poolAlloc[i];
            if (prevAllocPoint != _poolAlloc[i]) {
                updateStakingPool();
            }
            poolInfo[i+1].depositFeeBP = _depositFeeBP[i];
		}

        //TIMELOCK THIS FUNCTION AS SOON AS IT IS CALLED
        timelock(Functions.SETLIST);
    }

    // 720-hour TimeLocked
    function updateMultiplier(uint256 multiplierNumber) public onlyOwner notLocked(Functions.UPDATEMULTIPLIER) {
        require(multiplierNumber <= 5, 'multipler too high');
        bonusMultiplier = multiplierNumber;

        //TIMELOCK THIS FUNCTION AS SOON AS IT IS CALLED
        timelock(Functions.UPDATEMULTIPLIER);
    }

    // 720-hour TimeLocked
    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _bep20PerBlock) public onlyOwner notLocked(Functions.UPDATEEMISSIONRATE) {
        require(_bep20PerBlock <= 1000000000000000000, 'must be smaller than the initial emission rate');
        massUpdatePools();
        bep20PerBlock = _bep20PerBlock;
        emit UpdateEmissionRate(msg.sender, _bep20PerBlock);

        //TIMELOCK THIS FUNCTION AS SOON AS IT IS CALLED
        timelock(Functions.UPDATEEMISSIONRATE);
    }

    // 720-hour TimeLocked
    function upgrade(address _address) public onlyOwner notLocked(Functions.UPGRADE) {
        bep20.transferOwnership(_address);
        bep20stake.transferOwnership(_address);

        //TIMELOCK THIS FUNCTION AS SOON AS IT IS CALLED
        timelock(Functions.UPGRADE);
    }

    // Read Only
    // View function to see pending BEP20s on frontend.
    function pendingBep20(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accBep20PerShare = pool.accBep20PerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 bep20Reward = multiplier.mul(bep20PerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accBep20PerShare = accBep20PerShare.add(bep20Reward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accBep20PerShare).div(1e12).sub(user.rewardDebt);
    }

    function pendingBep20All(address _user) public view returns (uint256) {
        uint256 pending = 0;
        for (uint256 pid = 0; pid < poolLength(); ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            UserInfo storage user = userInfo[pid][_user];
            if (user.amount == 0 || pool.allocPoint == 0) {
                continue;
            }
            pending = pending.add(pendingBep20(pid, _user));
        }
        return pending;
    }

    // Can Be Called By Anyone
    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Can Be Called By Anyone
    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 bep20Reward = multiplier.mul(bep20PerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        bep20.mint(devaddr, bep20Reward.div(10));
        bep20.mint(address(this), bep20Reward);
        pool.accBep20PerShare = pool.accBep20PerShare.add(bep20Reward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Non-Reentrant, Can Be Called By Anyone
    // Deposit LP tokens to MasterChef for BEP20 allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accBep20PerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeBep20Transfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
            _userIn(msg.sender);
            userList.push(msg.sender);
        }
        user.rewardDebt = user.amount.mul(pool.accBep20PerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Non-Reentrant, Can Be Called By Anyone
    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accBep20PerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeBep20Transfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            //update userIsIn array
            _userIn(msg.sender);
        }
        user.rewardDebt = user.amount.mul(pool.accBep20PerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Non-Reentrant, Can Be Called By Anyone
    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        _userIn(msg.sender);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe Function
    // Safe bep20 transfer function, just in case if rounding error causes pool to not have enough BEP20s.
    function safeBep20Transfer(address _to, uint256 _amount) internal {
        uint256 bep20Bal = bep20.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > bep20Bal) {
            transferSuccess = bep20.transfer(_to, bep20Bal);
        } else {
            transferSuccess = bep20.transfer(_to, _amount);
        }
        require(transferSuccess, "safeBep20Transfer: transfer failed");
    }

    // Safe Function
    // Update dev address by the owner.
    function dev(address _devaddr) public onlyOwner {
        devaddr = _devaddr;
        emit SetDevAddress(msg.sender, _devaddr);
    }

    // Safe Function
    // Update fee address by the owner.
    function setFeeAddress(address _feeAddress) public onlyOwner {
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }
}