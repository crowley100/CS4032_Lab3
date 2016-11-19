module Main where
 
import System.IO
import GHC.IO.Handle
import System.Exit
import System.Environment
import Network.Socket
import Network.BSD
import Control.Exception
import Control.Concurrent
import Control.Concurrent.STM
import Control.Monad
import Control.Monad.Fix (fix)
import Data.List.Split
import Data.List
import Data.Map 
import Data.Maybe
import qualified Data.Map as Map

myPool = 100

threadPoolIO :: Int -> (a -> IO b) -> IO (Chan a, Chan b)
threadPoolIO nr mutator = do
    input <- newChan
    output <- newChan
    forM_ [1..nr] $
        \_ -> forkIO (forever $ do
            i <- readChan input
            o <- mutator i
            writeChan output o)
    return (input, output)

-- init
runServer :: Int -> IO ()
runServer port = do
    sock <- socket AF_INET Stream 0            -- new socket
    setSocketOption sock ReuseAddr 1           -- make socket reuseable
    bind sock (SockAddrInet (fromIntegral port) iNADDR_ANY)   -- listen on port.
    listen sock 5
    t <- myThreadId
    let tstr = (words (show t)) !! 1
    mychan <- newChan
    let rooms = empty
    let names = empty
    let joinIds = singleton tstr t
    roomMap <- atomically $ newTVar rooms
    roomNames <- atomically $ newTVar names
    ids <- atomically $ newTVar joinIds
    (input,output) <- threadPoolIO myPool hdlConn   -- 50 workers
    mainLoop sock ids roomNames roomMap input port 0
  
-- handle connections  
mainLoop :: Socket -> TVar (Map String ThreadId) -> TVar (Map String String) -> TVar (Map String (Chan String)) -> Chan (MVar [String],Int,TVar (Map String ThreadId),TVar (Map String String), TVar (Map String (Chan String)), Int, Handle) -> Int -> Int -> IO ()
mainLoop sock ids roomNames roomMap input port cId = do
    (conn,_) <- accept sock     -- accept a new client connection
    handle <- socketToHandle conn ReadWriteMode
    hSetBuffering handle (BlockBuffering (Just 1))
    refs <- newMVar [] 
    writeChan input (refs,cId,ids,roomNames,roomMap,port,handle)
    mainLoop sock ids roomNames roomMap input port (cId+1) -- loop

getValidLine :: Handle -> IO String
getValidLine hdl = do
    h <- (hGetLine hdl)
    if (h == "")
    then getValidLine hdl
    else return h

-- server logic
hdlConn :: (MVar [String],Int,TVar (Map String ThreadId),TVar (Map String String), TVar (Map String (Chan String)), Int, Handle) -> IO ()
hdlConn (roomRefList,cId,idMap,roomNames,roomMap,port,handle) = do
    t <- myThreadId -- create parent thread here
    print ("THREAD EXECTUING: " ++ (show t))
    fix $ \loop -> do
        myHead <- getValidLine handle
        print ("header:" ++ myHead ++ " id:" ++ (show t))
        let header = ((splitOn ":" myHead) !!0)
            lineActions = repeat (hGetLine handle)
            pred = if (header == "CHAT")
                       then (isInfixOf "MESSAGE")
                       else (isInfixOf "CLIENT_NAME")
        lines <- if (myHead == "HELO BASE_TEST" || myHead == "KILL_SERVICE")
                        then return []
                        else ioTakeWhile pred lineActions
        let myLines = ([myHead] ++ lines)
            msg = concat myLines
        case header of
            "KILL_SERVICE" -> do
                hFlushAll handle
                hClose handle
                ids <- atomically $ readTVar idMap
                let parentThread = Map.lookup "1" ids
                killThread (fromJust parentThread)
            "HELO BASE_TEST" -> do 
                let hiMsg = myResponse msg "134.226.32.10" port
                hPutStr handle hiMsg
                hFlushAll handle
            "DISCONNECT" -> do
                t <- myThreadId
                refs <- readMVar roomRefList
                let len = length refs
                    cName = (splitColon $ myLines !! 2)
                rooms <- atomically $ readTVar roomMap
                broadcastDisc refs 0 len rooms cName
                threadDelay 700
                hClose handle
                killThread (t)
            "JOIN_CHATROOM" -> do
                let rName = (splitColon $ head myLines)
                    cName = (splitColon $ myLines !! 3)
                tId <- clientJoin roomRefList cId handle port roomNames rName cName roomMap
                nameMap <- atomically $ readTVar roomNames
                let myId = show cId
                    ref = fromJust (Map.lookup rName nameMap)
                let newId = (myId ++ ref) -- room ref
                atomically $ modifyTVar idMap (Map.insert newId tId)
                print ("newId: " ++ newId)
            "LEAVE_CHATROOM" -> do
                rooms <- atomically $ readTVar roomMap
                refs <- readMVar roomRefList
                let roomRef = ((words (splitColon $ head myLines))!!0)
                    joinId = ((words (splitColon $ myLines !! 1))!!0)
                    clientName = ((words (splitColon $ myLines !! 2))!!0)
                    echo = "LEFT_CHATROOM:" ++ roomRef ++ "\n" ++ "JOIN_ID:" ++ joinId
                ids <- atomically $ readTVar idMap
                let myIndex = joinId ++ roomRef
                case Map.lookup myIndex ids of
                    Nothing -> do
                        hPutStrLn handle echo
                    Just threadId -> do
                        let newRefs = Data.List.delete roomRef refs
                        swapMVar roomRefList newRefs
                        let chan = fromJust (Map.lookup roomRef rooms)
                        dupe <- dupChan chan
                        writeChan dupe (buildResponse roomRef clientName (clientName ++ " has left this chatroom."))
                        hPutStrLn handle echo
                        atomically $ modifyTVar idMap (Map.delete myIndex)
                        threadDelay 500
                        killThread threadId
            "CHAT" -> do
                rooms <- atomically $ readTVar roomMap
                ids <- atomically $ readTVar idMap
                let joinId = (words (splitColon $ myLines !! 1))!!0
                    roomRef = (words (splitColon $ head myLines))!!0
                let myIndex = (joinId++roomRef)
                case Map.lookup myIndex ids of
                    Nothing -> do
                        --print "hello orbison"
                        hPutStrLn handle (errmsg 5 "Must join chatroom first") -- not in channel, send error
                    Just _ -> do
                        --print "hello orb"
                        case Map.lookup roomRef rooms of
                            Nothing -> do
                                hPutStrLn handle (errmsg 0 "server error")
                            Just chan -> do
                                dupe <- dupChan chan
                                if (joinId /= "6")
                                    then writeChan dupe (head myLines ++ "\n" ++ (myLines !! 2) ++ "\n" ++ (myLines !! 3) ++ "\n")
                                    else do writeChan dupe (head myLines ++ "\n" ++ (myLines !! 2) ++ "\n" ++ (myLines !! 3) ++ "\n") -- end comms
                                            threadDelay 10
                                            print "closing..."
                                            let parentThread = Map.lookup "1" ids
                                            killThread (fromJust parentThread)
                
            _ -> putStrLn $ "Unknown Message:" ++ msg
        loop
    hClose handle

clientJoin :: MVar [String] -> Int -> Handle -> Int -> TVar (Map String String) -> String -> String -> TVar (Map String (Chan String)) -> IO ThreadId--IO ThreadId?
clientJoin roomRefList cId handle port roomNames roomName clientName roomMap = do
    nameMap <- atomically $ readTVar roomNames
    rooms <- atomically $ readTVar roomMap
    refs <- readMVar roomRefList
    let joinId = show cId
    case Map.lookup roomName nameMap of
        Nothing -> do -- does not exist (create&join)
            print "it does not exist"
            chan <- newChan
            dupe <- dupChan chan
            -- thread for reading from the duplicated channel
            listener <- forkIO $ fix $ \loop -> do
                        msg <- readChan dupe
                        hPutStrLn handle msg
                        loop
            
            atomically $ modifyTVar roomMap (Map.insert ((words (show listener)) !! 1) chan)
            atomically $ modifyTVar roomNames (Map.insert roomName ((words (show listener)) !! 1))
            let response = "JOINED_CHATROOM:" ++ roomName ++ "\n" ++
                           "SERVER_IP:134.226.32.10" ++ "\n" ++
                           "PORT:" ++ (show port) ++ "\n" ++
                           "ROOM_REF:" ++ ((words (show listener)) !! 1) ++ "\n" ++
                           "JOIN_ID:" ++ joinId
            let newRefs = Data.List.insert ((words (show listener)) !! 1) refs
            swapMVar roomRefList newRefs
            hPutStrLn handle response
            writeChan dupe (buildResponse ((words (show listener)) !! 1) clientName (clientName ++ " has joined this chatroom."))
            return listener
        Just roomRef -> do -- exists (join)
            print "it exists"
            case Map.lookup roomRef rooms of
                Nothing -> do
                    hPutStrLn handle (errmsg 0 "server error")
                    t <- myThreadId
                    return t -- generic return value
                Just channel -> do
                    dupe <- dupChan channel
                    -- thread for reading from the duplicated channel
                    listener <- forkIO $ fix $ \loop -> do
                        msg <- readChan dupe
                        hPutStrLn handle msg
                        loop
                    let response = "JOINED_CHATROOM:" ++ roomName ++ "\n" ++
                                   "SERVER_IP:134.226.32.10" ++ "\n" ++
                                   "PORT:" ++ (show port) ++ "\n" ++
                                   "ROOM_REF:" ++ roomRef ++ "\n" ++
                                   "JOIN_ID:" ++ joinId
                    let newRefs = Data.List.insert roomRef refs
                    swapMVar roomRefList newRefs
                    hPutStrLn handle response
                    print ("client name: " ++ clientName)
                    writeChan dupe (buildResponse roomRef clientName (clientName ++ " has joined this chatroom."))
                    return listener

buildResponse :: String -> String -> String -> String
buildResponse roomRef clientName msg = "CHAT:" ++ roomRef ++ "\n" ++
                                       "CLIENT_NAME:" ++ clientName ++ "\n" ++
                                       "MESSAGE:" ++ msg ++ "\n" -- with \n?

myResponse :: String -> String -> Int -> String
myResponse msg host port = msg ++ "\n" ++
                           "IP:" ++ host ++ "\n" ++
                           "Port:" ++ show port ++ "\n" ++
                           "StudentID:13333179"
                           
errmsg :: Int -> String -> String
errmsg code desc = "ERROR_CODE: " ++ show code ++ "\n" ++
                   "ERROR_DESCRIPTION: " ++ desc  
                   
broadcastDisc :: [String] -> Int -> Int -> Map String (Chan String) -> String -> IO ()
broadcastDisc refs i end rooms cName | i < end = do
                                            let myRef = refs !! i
                                            case Map.lookup myRef rooms of
                                                Nothing -> do
                                                    broadcastDisc refs (i+1) end rooms cName
                                                Just chan -> do
                                                    dupe <- dupChan chan
                                                    writeChan dupe (buildResponse myRef cName (cName ++ " has left this chatroom."))
                                                    threadDelay 10
                                                    broadcastDisc refs (i+1) end rooms cName
                                       | otherwise = return ()

                      
splitColon :: String -> String
splitColon str = (splitOn ":" str) !! 1
    
ioTakeWhile :: (String -> Bool) -> [IO String] -> IO [String]
ioTakeWhile pred actions = do
  x <- (head actions)
  if (pred x)
    then return [x]
    else (ioTakeWhile pred (tail actions)) >>= \xs -> return (x:xs)

main :: IO ()
main = withSocketsDo $ do
    args <- getArgs
    let port = read $ head args :: Int
    runServer port
