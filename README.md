# haskell-secureUDP
Haskell module for secure UDP packet transfer.

- Packets are guaranteed to be received (and as fast as possible).
- Packets are NOT guaranteed to arrive in order.
- Packets are NOT guaranteed to arrive just once.
- It's recommended that on the ChannelConfig, the maxPacketSize isn't set to a value
    larger than 500.
