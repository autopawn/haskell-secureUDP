# haskell-secureUDP

Haskell module for secure UDP packet transfer.

- Packets are guaranteed to be received (and as fast as possible).
- Packets are NOT guaranteed to arrive in order.
- Packets are NOT guaranteed to arrive just once.

## Notes:

- It's recommended that on the ChannelConfig, the maxPacketSize isn't set to a value
    larger than 500. Theoretically the IP protocol should partition packages larger than the MTU,
    however the packages could be dropped.
- To avoid communication problems, all communicating channels should have the same ChannelConfig,
    except by the `socket` or the `allowed` function.
