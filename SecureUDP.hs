module SecureUDP (
    startChannel,
    ChannelConfig(..),
    getReceived,
    getLoss,
    sendMessages,
    ChannelSt
) where

import Auxiliars
import Channel

import qualified Control.Concurrent as C

import qualified Data.Set as S
import qualified Data.ByteString as Bs
import qualified System.CPUTime as T

import qualified Network.Socket as So hiding (send, sendTo, recv, recvFrom)
import qualified Network.Socket.ByteString as B

type ChannelSt = C.MVar ChannelStatus

getReceived :: C.MVar ChannelStatus -> IO ([(So.SockAddr,Bs.ByteString)])
getReceived mchst = do
    chst <- C.takeMVar mchst
    let chst' = chst {recvMsgs = []}
    C.putMVar mchst $! chst'
    return (recvMsgs chst)

getLoss :: C.MVar ChannelStatus -> IO ([(So.SockAddr,Bs.ByteString)])
getLoss mchst = do
    chst <- C.takeMVar mchst
    let chst' = chst {unsentMsgs = S.empty}
    C.putMVar mchst $! chst'
    return (map (\(Message _ addr str _ _) -> (addr,str)) $ S.toList $ unsentMsgs chst)

sendMessages :: C.MVar ChannelStatus -> [(So.SockAddr,Bs.ByteString)] -> IO ()
sendMessages mchst msgs = do
    chst <- C.takeMVar mchst
    let chst' = foldr queueMsg chst msgs
    C.putMVar mchst $! chst'

startChannel :: ChannelConfig -> IO (C.MVar ChannelStatus)
-- ^ Starts a sending and a receiving threads for the protocol, returns an MVar that can be used
-- to insert and extract messages.
startChannel chcfg = do
    mchst <- C.newMVar emptyChannel
    _ <- C.forkIO (receptionChannel chcfg mchst)
    _ <- C.forkIO (sendingChannel chcfg mchst)
    return mchst

sendingChannel :: ChannelConfig ->  C.MVar ChannelStatus -> IO ()
-- ^ Execution that sends messages (if there are on the ChannelStatus).
sendingChannel chcfg mchst = do
    chst <- C.takeMVar mchst
    time <- T.getCPUTime
    let (msgs,chst') = nextForSending chcfg time chst
    C.putMVar mchst $! chst'
    let bstr m = Bs.pack $ char2word8 'm' : dataInt (msgId m) ++ Bs.unpack (string m)
    let send m = B.sendTo (socket chcfg) (bstr m) (address m)
    mapM_ send msgs
    sendingChannel chcfg mchst


receptionChannel :: ChannelConfig -> C.MVar ChannelStatus -> IO ()
-- ^ Execution that receives messages and returns their ACKs.
receptionChannel chcfg mchst = do
    (bString,sAddr) <- B.recvFrom (socket chcfg) (maxPacketSize chcfg + 4)
    if (allowed chcfg) sAddr then
        let (kind,ide,msg) = bstrKind bString
        in if kind=='m' then do
            _ <- B.sendTo (socket chcfg) (Bs.pack $ char2word8 'a' : dataInt ide) sAddr
            chst <- C.takeMVar mchst
            let chst' = receiveMsg (sAddr,msg) chst
            C.putMVar mchst $! chst'
        else if kind=='a' then do
            chst <- C.takeMVar mchst
            let chst' = registerACK sAddr ide chst
            C.putMVar mchst $! chst'
        else return ()
    else return ()
    receptionChannel chcfg mchst
