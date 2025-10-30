# Technical Specification for Fixing Start Service and Stop Service Functionality

## Problem Analysis
- **PPP Interfaces:** PPP interfaces stay DOWN, leading to connectivity issues.
- **RuntimeError:** A RuntimeError occurs due to too many threads being spawned without proper management.
- **Connection Verification:** There is a missing verification step for the connections established.

## Solution Requirements
1. **service_manager.py Enhancements:**  
   - Implement a mechanism to properly wait for the PPP interface to achieve an UP state, including a timeout feature.  
   - Limit concurrent connections to a maximum of 5 nodes to prevent overloading the system.  
   - Introduce a function `_is_ppp_interface_up` that checks if the interface is UP and has the POINTOPOINT flags set.  
   - Add a function `_wait_for_ppp_connect` that parses pppd logs for the “Connect” message, ensuring the connection is established before proceeding.  
   - Implement a graceful `stop_service` function that cleanly stops all running pppd processes and the danted service.

2. **pptp_tunnel_manager.py Update:**  
   - Modify this script to include a verification step that confirms the connection is valid before returning control to the calling function.

3. **Backend Service Configuration:**  
   - Add the command `ulimit -n 4096` to the backend service to increase the maximum number of open file descriptors.
   - Ensure that the script `link_socks_to_ppp.sh` has the necessary execute permissions set.

## Validation Criteria
- The interface `ppp0-ppp4` should be confirmed to be in the UP state.
- The output from `netstat` must show that ports 1080-1085 are in the listening state.
- The logs should no longer contain any RuntimeError messages.
- The Stop Service functionality should terminate all processes cleanly without leaving any orphaned instances.
