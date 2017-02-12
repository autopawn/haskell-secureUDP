module Channel where

import qualified Data.ByteString as Bs
import qualified Data.Set as S

import qualified Control.Concurrent as C (ThreadId)
import qualified Network.Socket as So hiding (send, sendTo, recv, recvFrom)

-- | Holds the configuration of a channel.
data ChannelConfig = ChannelConfig {
    socket :: So.Socket,
    -- ^ The UDP Socket from Network.Socket that the channel will use to send and receive
    -- messages.
    resendTimeout :: Integer,
    -- ^ Picoseconds after a package is re-send if no ACK for it is received.
    maxResends :: Int,
    -- ^ Times that the same package can be re-sended without ACK after considerating it
    -- lost.
    allowed :: So.SockAddr -> IO(Bool),
    -- ^ Function used to determinate if accept or not incomming packages from the given
    -- address.
    maxPacketSize :: Int,
    -- ^ Max bytes that can be sent on this channel packages, larger packages will throw
    -- and exception.
    recvRetention :: Integer
    -- ^ Time that a received and delivired package will remain on memory in order to avoid
    -- duplicated receptions.
    -- The packages will be stored @recvRetention *resendTimeout * maxResends@ picoseconds after
    -- reception and after that, will be freed on the next getReceived call.
}

data ChannelStatus = ChannelStatus {
    nextId :: !Int,
    sentMsgs :: !(S.Set Message),
    unsentMsgs :: !(S.Set Message),
    recvMsgs :: !(S.Set Message),
    deliveredMsgs :: !(S.Set Message),
    receivingThread :: !C.ThreadId,
    sendingThread :: !C.ThreadId,
    closed :: !Bool
} deriving (Show)

data Message = Message {
    msgId :: !Int,
    address :: !So.SockAddr,
    string :: !Bs.ByteString,
    lastSend :: !Integer, -- or reception time in case of incomming messages.
    resends :: !Int
} deriving (Show)

instance Eq Message where
    (==) m1 m2 = msgId m1 == msgId m2 && address m1 == address m2
instance Ord Message where
    compare m1 m2 = compare (msgId m1, address m1) (msgId m2, address m2)

emptyChannel :: C.ThreadId -> C.ThreadId -> ChannelStatus
emptyChannel rtid stid = ChannelStatus 0 S.empty S.empty S.empty S.empty rtid stid False

receiveMsg :: Message -> ChannelStatus -> ChannelStatus
-- ^ Queues a message that has been received.
receiveMsg msg chst =
    if S.notMember msg (deliveredMsgs chst) then
        chst {recvMsgs = S.insert msg (recvMsgs chst)}
    else chst

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
    in seq touted' $ (ready,chst')

nextForDeliver :: ChannelConfig -> Integer -> ChannelStatus -> (S.Set Message, ChannelStatus)
-- ^ Receives the current CPUTime and a ChannelStatus, returns the messages that can be delivered
-- and cleans the old ones that where retained.
nextForDeliver chcfg time chst = let
    retenTime = recvRetention chcfg * resendTimeout chcfg * fromIntegral (maxResends chcfg)
    survives m = time <= lastSend m + retenTime
    newDelivered = S.difference (S.filter survives (deliveredMsgs chst)) (recvMsgs chst)
    in (recvMsgs chst, chst {deliveredMsgs = newDelivered, recvMsgs = S.empty})
