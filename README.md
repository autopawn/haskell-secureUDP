# haskell-secureUDP
Haskell module for secure UDP packet transfer.

- Packets are guaranteed to be received (and as fast as possible).
- Packets are NOT guaranteed to arrive in order.
- Packets are NOT guaranteed to arrive just once.
- Packets musn't be larger than 500 bytes (and it's recommended that they are of less than 300).
