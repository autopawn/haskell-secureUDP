module SecureUDP (
    startChannel, closeChannel, checkClosed,
    ChannelConfig(..),
    getReceived, lookReceived,
    getLoss, lookLoss,
    sendMessages, channelConf,
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

type ChannelSt = (ChannelConfig, C.MVar ChannelStatus)

channelConf :: ChannelSt -> ChannelConfig
channelConf (chcfg,_) = chcfg

getReceived :: ChannelSt -> IO ([(So.SockAddr,Bs.ByteString)])
getReceived (_,mchst) = do
    chst <- C.takeMVar mchst
    let chst' = chst {recvMsgs = []}
    C.putMVar mchst $! chst'
    return (recvMsgs chst)

lookReceived :: ChannelSt -> IO ([(So.SockAddr,Bs.ByteString)])
lookReceived (_,mchst) = do
    chst <- C.readMVar mchst
    return (recvMsgs chst)

getLoss :: ChannelSt -> IO ([(So.SockAddr,Bs.ByteString)])
getLoss (_,mchst) = do
    chst <- C.takeMVar mchst
    let chst' = chst {unsentMsgs = S.empty}
    C.putMVar mchst $! chst'
    return (map (\(Message _ addr str _ _) -> (addr,str)) $ S.toList $ unsentMsgs chst)

lookLoss :: ChannelSt -> IO ([(So.SockAddr,Bs.ByteString)])
lookLoss (_,mchst) = do
    chst <- C.readMVar mchst
    return (map (\(Message _ addr str _ _) -> (addr,str)) $ S.toList $ unsentMsgs chst)

sendMessages :: ChannelSt -> [(So.SockAddr,Bs.ByteString)] -> IO (Bool)
sendMessages (chcfg,mchst) msgs = do
    chst <- C.takeMVar mchst
    if not (closed chst) then let
        checkAndqueue m =
            if Bs.length (snd m) <= maxPacketSize chcfg then queueMsg m
            else error "Package exceeded maxPacketSize."
        chst' = foldr checkAndqueue chst msgs
        in (C.putMVar mchst $! chst') >> return (True)
    else (C.putMVar mchst $! chst) >> return (False)


startChannel :: ChannelConfig -> IO (ChannelSt)
-- ^ Starts a sending and a receiving threads for the protocol, returns an MVar that can be used
-- to insert and extract messages.
startChannel chcfg = do
    mchst <- C.newEmptyMVar
    rtid <- C.forkIO (receptionChannel chcfg mchst)
    stid <- C.forkIO (sendingChannel chcfg mchst)
    C.putMVar mchst $! emptyChannel rtid stid
    return (chcfg, mchst)

closeChannel :: ChannelSt -> IO ()
closeChannel (_,mchst) = do
    chst <- C.takeMVar mchst
    if not (closed chst) then do
        C.killThread $ receivingThread chst
        C.killThread $ sendingThread chst
        let chst' = chst {closed = True}
        C.putMVar mchst $! chst'
    else
        C.putMVar mchst $! chst

checkClosed :: C.MVar ChannelStatus -> IO (Bool)
checkClosed mchst = do
    chst <- C.readMVar mchst
    return (closed chst)

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
    addrAllowed <- (allowed chcfg) sAddr
    if addrAllowed then
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
