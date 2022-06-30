// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import { LibDeploy } from "./libraries/LibDeploy.sol";

contract DeployScript is Script {
    function run() external {
        // HACK: https://github.com/foundry-rs/foundry/issues/2110
        uint256 nonce = vm.getNonce(msg.sender);
        console.log("vm.getNonce", vm.getNonce(msg.sender));
        vm.startBroadcast();

        address profileProxy = address(
            0x701A5baBA0701e3B1Dd3107dF47dDC68eaC019bf
        );
        string
            memory templateURL = "https://cyberconnect.mypinata.cloud/ipfs/bafkreigc6pzmqid6sy4owqotqekjl42s25flghijkyrykdm5m4jwcbhsdu";

        // TODO: pass in profileProxy to run a require. need some workaround right now the stack is too deep
        LibDeploy.deploy(msg.sender, nonce, templateURL);
        // TODO: set correct role capacity
        // TODO: do a health check. verify everything
        vm.stopBroadcast();
    }
}
