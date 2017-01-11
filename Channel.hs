module Channel where

import qualified Data.ByteString as Bs
import qualified Data.Set as S

import qualified Network.Socket as So hiding (send, sendTo, recv, recvFrom)

data ChannelConfig = ChannelConfig {
    socket :: So.Socket,
    resendTimeout :: Integer,
    maxResends :: Int,
    allowed :: So.SockAddr -> Bool,
    maxPacketSize :: Int
}

data ChannelStatus = ChannelStatus {
    nextId :: Int,
    sentMsgs :: !(S.Set Message), -- unACKed sent messages.
    unsentMsgs :: !(S.Set Message),
    recvMsgs :: [(So.SockAddr,Bs.ByteString)]
} deriving (Show)

data Message = Message {
    msgId :: Int,
    address :: So.SockAddr,
    string :: Bs.ByteString,
    lastSend :: Integer,
    resends :: Int
} deriving (Show)

instance Eq Message where
    (==) m1 m2 = msgId m1 == msgId m2 && address m1 == address m2
instance Ord Message where
    compare m1 m2 = compare (msgId m1, address m1) (msgId m2, address m2)

emptyChannel :: ChannelStatus
emptyChannel = ChannelStatus 0 S.empty S.empty []

receiveMsg :: (So.SockAddr,Bs.ByteString) -> ChannelStatus -> ChannelStatus
-- ^ Queues a message that has been received.
receiveMsg msg chst =
    chst {recvMsgs = msg : recvMsgs chst}

registerACK :: So.SockAddr -> Int -> ChannelStatus -> ChannelStatus
-- ^ Informs the ChannelStatus that it no longer needs to store the package from the address with
-- the given id , since it was ACKed from the remote host.
registerACK addr mId chst = chst {
        sentMsgs = S.delete (Message mId addr Bs.empty 0 0) (sentMsgs chst)
    }

queueMsg :: (So.SockAddr,Bs.ByteString) -> ChannelStatus -> ChannelStatus
-- ^ Puts a new message to be sent on the ChannelStatus.
queueMsg (addr,str) chst = chst {
        nextId = max 0 $ (nextId chst) + 1,
        sentMsgs = S.insert (Message (nextId chst) addr str 0 0) (sentMsgs chst)
    }

nextForSending :: ChannelConfig -> Integer -> ChannelStatus -> (S.Set Message, ChannelStatus)
-- ^ Receives the current CPUTime and a ChannelStatus, returns the messages to be sent and updates
-- the ChannelStatus, assuming that they will be sent.
nextForSending chcfg time chst = let
    touted = S.filter (\m -> time >= (lastSend m) + (resendTimeout chcfg)) (sentMsgs chst)
    touted' = S.map (\m -> m {lastSend = time, resends = resends m + 1}) touted
    (ready,failed) = S.partition (\m -> resends m <= maxResends chcfg) touted'
    updatedMsgs = S.union ready $ S.difference (sentMsgs chst) failed
    chst' = chst {sentMsgs = updatedMsgs, unsentMsgs = S.union failed (unsentMsgs chst)}
    in (ready,chst')
