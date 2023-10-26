// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
pragma abicoder v2;

import "sync-swap/contracts/interfaces/IRouter.sol";
import "sync-swap/contracts/SyncSwapRouter.sol";



import {IPaymaster, ExecutionResult, PAYMASTER_VALIDATION_SUCCESS_MAGIC} from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymaster.sol";
import {IPaymasterFlow} from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymasterFlow.sol";
import {TransactionHelper, Transaction} from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";

import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "hardhat/console.sol";


contract Swapmaster is IPaymaster {
    // uint256 constant PRICE_FOR_PAYING_FEES = 1;

    SyncSwapRouter public immutable swapRouter;

   address public constant WETH9 = 0x5AEa5775959fBC2557Cc8789bC1bf90A239D9a91;
   address public constant USDC = 0x3355df6D4c9C3035724Fd0e3914dE96A5a83aaf4;
   address public constant swapRouterAddr = 0x2da10A1e27bF85cEdD8FFb1AbBe97e53391C0295;
   address public constant swapPool = 0x80115c708E12eDd42E504c1cD52Aea96C547c05c; //TODO get this dynamically

    modifier onlyBootloader() {
        require(
            msg.sender == BOOTLOADER_FORMAL_ADDRESS,
            "Only bootloader can call this method"
        );
        // Continue execution if called from the bootloader.
        _;
    }

    constructor() {
        swapRouter = SyncSwapRouter(swapRouterAddr);
    }

    function validateAndPayForPaymasterTransaction(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    )
        external
        payable
        onlyBootloader
        returns (bytes4 magic, bytes memory context)
    {
        console.log("In Swapmaster");
        // By default we consider the transaction as accepted.
        magic = PAYMASTER_VALIDATION_SUCCESS_MAGIC;
        require(
            _transaction.paymasterInput.length >= 4,
            "The standard paymaster input must be at least 4 bytes long"
        );

        bytes4 paymasterInputSelector = bytes4(
            _transaction.paymasterInput[0:4]
        );
        if (paymasterInputSelector == IPaymasterFlow.approvalBased.selector) {
            // While the transaction data consists of address, uint256 and bytes data,
            // the data is not needed for this paymaster
            (address token, uint256 amount, bytes memory data) = abi.decode(
                _transaction.paymasterInput[4:],
                (address, uint256, bytes)
            );

            // Verify if token is the correct one
            // require(token == allowedToken, "Invalid token");

            // We verify that the user has provided enough allowance
            address userAddress = address(uint160(_transaction.from));
            // address toAddress = address(uint160(_transaction.to));

            address thisAddress = address(this);

            // uint256 providedAllowance = IERC20(token).allowance(
            //     userAddress,
            //     thisAddress
            // );
            // require(
            //     providedAllowance >= PRICE_FOR_PAYING_FEES,
            //     "Min allowance too low"
            // );
            console.log(amount);

            // Note, that while the minimal amount of ETH needed is tx.gasPrice * tx.gasLimit,
            // neither paymaster nor account are allowed to access this context variable.
            uint256 requiredETH = _transaction.gasLimit *
                _transaction.maxFeePerGas;
            // bytes memory testSwapData = abi.encode(["address", "address", "uint8"], [token, thisAddress, 1]);
            bytes memory testSwapData = abi.encode(token, thisAddress, 1);
            console.log(string(testSwapData));


            // try
            //     IERC20(token).transferFrom(userAddress, thisAddress, amount)
            // {} catch (bytes memory revertReason) {
            //     // If the revert reason is empty or represented by just a function selector,
            //     // we replace the error with a more user-friendly message
            //     if (revertReason.length <= 4) {
            //         revert("Failed to transferFrom from users' account");
            //     } else {
            //         assembly {
            //             revert(add(0x20, revertReason), mload(revertReason))
            //         }
            //     }
            // }
            swapSingle(amount, testSwapData, userAddress);

            // The bootloader never returns any data, so it can safely be ignored here.
            (bool success, ) = payable(BOOTLOADER_FORMAL_ADDRESS).call{
                value: requiredETH
            }("");
            require(
                success,
                "Failed to transfer tx fee to the bootloader. Paymaster balance might not be enough."
            );
        } else {
            revert("Unsupported paymaster flow");
        }
    }

    /// @dev The calling address must approve this contract to spend at least `amountIn` worth of its USDC for this function to succeed.
    /// @param amountIn The exact amount of USDC that will be swapped for ETH.
    /// @param swapData The data to be swapped [tokenIn, to, withdraw mode]
    /// @return amountOut The amount of ETH received.
    function swapSingle(uint256 amountIn, bytes memory swapData, address userAddress) public returns (uint256 amountOut) { //TODO make internal
        // msg.sender must approve this contract
        console.log(string(swapData));
        console.log(amountIn);

        // Transfer the specified amount of USDC to this contract.
        // TransferHelper.safeTransferFrom(USDC, msg.sender, address(this), amountIn);
        TransferHelper.safeTransferFrom(USDC, userAddress, address(this), amountIn);
        console.log("Here");

        // Approve the router to spend USDC.
        TransferHelper.safeApprove(USDC, address(swapRouter), amountIn);
        console.log("Here 1");


        IRouter.SwapStep memory swapStep1 = IRouter.SwapStep({
            pool: swapPool,
            data: swapData, //TODO generate swapData in the contract
            callback: address(0),
            callbackData: "" 
        });
        console.log("Here 2");

        IRouter.SwapStep[] memory swapStep = new IRouter.SwapStep[](1);
        swapStep[0] = swapStep1;
        console.log("Here 3");

        IRouter.SwapPath[] memory swapPaths = new IRouter.SwapPath[](1);
        swapPaths[0] = IRouter.SwapPath({
            steps: swapStep,
            tokenIn: USDC,
            amountIn: amountIn
        });
        console.log("Here 4");

        // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
        uint32 minOut = 0;
        uint32 deadline = 1694139428; //30 mins
        IPool.TokenAmount memory tokenAmount = swapRouter.swap(swapPaths, minOut, deadline);
        return tokenAmount.amount;
    }

    function postTransaction(
        bytes calldata _context,
        Transaction calldata _transaction,
        bytes32,
        bytes32,
        ExecutionResult _txResult,
        uint256 _maxRefundedGas
    ) external payable override onlyBootloader {
    }

    receive() external payable {}
}
