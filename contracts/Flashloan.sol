// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./uniswap/IUniswapV2Router02.sol";
import "./uniswap/v3/ISwapRouter.sol";

import "./dodo/IDODO.sol";
import "./dodo/IDODOProxy.sol";
import "./interfaces/IFlashloan.sol";
import "./base/FlashloanValidation.sol";
import "./base/DodoBase.sol";
import "./libraries/BytesLib.sol";
import "./libraries/Part.sol";
import "./libraries/RouteUtils.sol";

import "hardhat/console.sol";

contract Flashloan is IFlashloan, FlashloanValidation, DodoBase {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using BytesLib for bytes;

    event SentProfit(address recipient, uint256 profit);
    event SwapFinished(address token, uint256 amount);

    function dodoFlashLoan(FlashParams memory params)
        external
        checkParams(params)
    {
        bytes memory data = abi.encode(
            FlashCallbackData({
                me: msg.sender,
                flashLoanPool: params.flashLoanPool,
                loanAmount: params.loanAmount,
                firstRoutes: params.firstRoutes,
                secondRoutes: params.secondRoutes
            })
        );

        address loanToken = RouteUtils.getInitialToken(params.firstRoutes[0]);
        if (IDODO(params.flashLoanPool)._BASE_TOKEN_() == loanToken) {
            IDODO(params.flashLoanPool).flashLoan(
                params.loanAmount,
                0,
                address(this),
                data
            );
        } else if (IDODO(params.flashLoanPool)._QUOTE_TOKEN_() == loanToken) {
            IDODO(params.flashLoanPool).flashLoan(
                0,
                params.loanAmount,
                address(this),
                data
            );
        }
    }

    function _flashLoanCallBack(
        address,
        uint256,
        uint256,
        bytes calldata data
    ) internal override {
        FlashCallbackData memory decoded = abi.decode(
            data,
            (FlashCallbackData)
        );

        address loanToken = RouteUtils.getInitialToken(decoded.firstRoutes[0]);
        address toToken = RouteUtils.getInitialToken(decoded.secondRoutes[0]);

        require(
            IERC20(loanToken).balanceOf(address(this)) >= decoded.loanAmount,
            "Failed to borrow loan token"
        );

        for (uint256 i = 0; i < decoded.firstRoutes.length; i++) {
            uint256 amountIn = Part.partToAmountIn(
                decoded.firstRoutes[i].part,
                decoded.loanAmount
            );
            console.log("callback amountIn", amountIn);
            routeTrade(decoded.firstRoutes[i], amountIn);
        }

        uint256 toTokenAmount = IERC20(toToken).balanceOf(address(this));

        for (uint256 i = 0; i < decoded.secondRoutes.length; i++) {
            uint256 amountIn = Part.partToAmountIn(
                decoded.secondRoutes[i].part,
                toTokenAmount
            );
            console.log("amountIn", amountIn);
            routeTrade(decoded.secondRoutes[i], amountIn);
        }

        emit SwapFinished(
            loanToken,
            IERC20(loanToken).balanceOf(address(this))
        );

        require(
            IERC20(loanToken).balanceOf(address(this)) >= decoded.loanAmount,
            "Not enough amount to return loan"
        );
        //Return funds
        IERC20(loanToken).transfer(decoded.flashLoanPool, decoded.loanAmount);

        // send all loanToken to msg.sender
        uint256 remained = IERC20(loanToken).balanceOf(address(this));
        IERC20(loanToken).transfer(decoded.me, remained);
        emit SentProfit(decoded.me, remained);
    }

    function routeTrade(Route memory route, uint256 totalAmount) internal {
        uint256 amountIn = totalAmount;
        for (uint256 i = 0; i < route.hops.length; i++) {
console.log("amountIn", amountIn);
            amountIn = hopTrade(route.hops[i], amountIn);
        }
    }

    function hopTrade(Hop memory hop, uint256 totalAmount) internal returns (uint256) {
        uint256 amountOut = 0;
        for (uint256 i = 0; i < hop.swaps.length; i++) {
            uint256 amountIn = Part.partToAmountIn(
                hop.swaps[i].part,
                totalAmount
            );
            amountOut += pickProtocol(hop.swaps[i], hop.path, amountIn);
        }
        return amountOut;
    }

    function pickProtocol(
        Swap memory swap,
        address[] memory path,
     uint256 amountIn
     )
        internal
        // checkRouteProtocol(swap)
        returns (uint256 amountOut)
    {
console.log("pick protocol amountIn", amountIn);
return uniswapV2(swap, path, amountIn)[1];

        // if (swap.protocol == 0) {
        //     // dodoSwap(swap, amountIn);
        // } else if (swap.protocol == 1) {
        //     uniswapV2(swap, amountIn);
        // } else if (swap.protocol == 2) {
        //     uniswapV3(swap, tokenIn, tokenOut, amountIn);
        // }
    }

//     function uniswapV3(
//         Swap memory swap,
//         address[] memory path,
//         uint256 amountIn
//     ) internal 
//     // checkRouteUniswapV3(swap) 
//     returns (uint256 amountOut) {
//         ISwapRouter swapRouter = ISwapRouter(swap.router);
//         approveToken(path[0], address(swapRouter), amountIn);

// console.log("amountIn", amountIn);
//             // single swaps
//             amountOut = swapRouter.exactInputSingle(
//                 ISwapRouter.ExactInputSingleParams({
//                     tokenIn: tokenIn,
//                     tokenOut: tokenOut,
//                     // fee: swap.fee[0],
//                     fee: 500,
//                     recipient: address(this),
//                     deadline: block.timestamp,
//                     amountIn: amountIn,
//                     amountOutMinimum: 0,
//                     sqrtPriceLimitX96: 0
//                 })
//             );
//         //     // multihop swaps
//         //     bytes memory tokenFee = "";
//         //     for (uint8 i = 0; i < swap.path.length - 1; i++) {
//         //         tokenFee = tokenFee.merge(
//         //             abi.encodePacked(swap.path[i], swap.fee[i])
//         //         );
//         //     }

//         //     amountOut = swapRouter.exactInput(
//         //         ISwapRouter.ExactInputParams({
//         //             path: tokenFee.merge(
//         //                 abi.encodePacked(swap.path[swap.path.length - 1])
//         //             ),
//         //             recipient: address(this),
//         //             deadline: block.timestamp,
//         //             amountIn: amountIn,
//         //             amountOutMinimum: 0
//         //         })
//         //     );
//     }

    function uniswapV2(
        Swap memory swap,
        address[] memory path,
        uint256 amountIn
    ) internal returns (uint256[] memory) {

console.log("univ2 amountIn", amountIn);
        approveToken(path[0], swap.router, amountIn);
        return
            IUniswapV2Router02(swap.router).swapExactTokensForTokens(
                amountIn,
                1,
                path,
                address(this),
                block.timestamp
            );
    }

    // function dodoSwap(Swap memory swap, uint256 amountIn) internal {
    //     address fromToken = swap.path[0];
    //     address toToken = swap.path[1];
    //     address dodoV2Pool = swap.router;

    //     address[] memory dodoPairs = new address[](1); //one-hop
    //     dodoPairs[0] = dodoV2Pool;

    //     address baseToken = IDODO(dodoV2Pool)._BASE_TOKEN_();

    //     uint256 directions = baseToken == fromToken ? 0 : 1;

    //     // pool address validation
    //     if (directions == 0) {
    //         require(
    //             IDODO(dodoV2Pool)._QUOTE_TOKEN_() == toToken,
    //             "Wrong dodo V2 pool address"
    //         );
    //     } else {
    //         require(
    //             IDODO(dodoV2Pool)._BASE_TOKEN_() == toToken,
    //             "Wrong dodo V2 pool address"
    //         );
    //     }

    //     uint256 deadline = block.timestamp;

    //     address dodoApprove = 0x6D310348d5c12009854DFCf72e0DF9027e8cb4f4;
    //     approveToken(fromToken, dodoApprove, amountIn);

    //     address dodoProxy = 0xa222e6a71D1A1Dd5F279805fbe38d5329C1d0e70;

    //     IDODOProxy(dodoProxy).dodoSwapV2TokenToToken(
    //         fromToken,
    //         toToken,
    //         amountIn,
    //         1,
    //         dodoPairs,
    //         directions,
    //         false,
    //         deadline
    //     );
    // }

    function approveToken(
        address token,
        address to,
        uint256 amountIn
    ) internal {
        require(IERC20(token).approve(to, amountIn), "approve failed.");
    }
}
