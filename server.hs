module Main where
 
import System.IO
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


myPool = 50

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
    listen sock 2  
    mychan <- newChan
    let rooms = empty
    let names = empty
    roomMap <- atomically $ newTVar rooms
    roomNames <- atomically $ newTVar names
    (input,output) <- threadPoolIO myPool hdlConn   -- 50 workers
    mainLoop sock roomNames roomMap input port
  
-- handle connections  
mainLoop :: Socket -> TVar (Map String String) -> TVar (Map String (Chan String)) -> Chan (MVar (Map String ThreadId),TVar (Map String String), TVar (Map String (Chan String)), Int, Handle) -> Int -> IO ()
mainLoop sock roomNames roomMap input port = do
    t <- myThreadId
    let tstr = (words (show t)) !! 1
    --print (tstr ++ " mainloop!")
    --print ("main line..." ++ (show t))
    (conn,_) <- accept sock     -- accept a new client connection
    handle <- socketToHandle conn ReadWriteMode
    hSetBuffering handle NoBuffering -- Line??
    ids <- newMVar (singleton tstr t)
    --let parentThread = Map.lookup "1" ids
    --print (fromJust parentThread) 
    writeChan input (ids,roomNames,roomMap,port,handle) -- pass id map in here (add to def for input chan) LOOK HERE FOR ID STUFF!!!
    mainLoop sock roomNames roomMap input port        -- loop

-- server logic
hdlConn :: (MVar (Map String ThreadId),TVar (Map String String), TVar (Map String (Chan String)), Int, Handle) -> IO ()
hdlConn (idMap,roomNames,roomMap,port,handle) = do
    t <- myThreadId
    print ("THREAD EXECTUING: " ++ (show t))
    fix $ \loop -> do
        let myIOHead = hGetLine handle
        myHead <- myIOHead
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
        print myLines
        -- error handling here: accepted <- try (handler params) case accepted of Left error Right finish
        
        print ("YO -> " ++ header)
        case header of
            "KILL_SERVICE" -> do
                hClose handle -- clean up first? os.exit...
                ids <- readMVar idMap
                let parentThread = Map.lookup "1" ids
                killThread (fromJust parentThread) 
            "HELO BASE_TEST" -> do 
                let hiMsg = myResponse msg "134.226.32.10" port
                print "hereNOW"
                --print hiMsg
                hPutStr handle hiMsg
                hClose handle
                t <- myThreadId
                killThread t
            "DISCONNECT" -> hClose handle --kill all threads first or handle exceptions and send response! (send all leave responses)
            "JOIN_CHATROOM" -> do 
                -- CHECK IF CLIENT IN ROOM HERE!!
                print "im here"
                tId <- clientJoin handle port roomNames (splitColon $ head myLines) (splitColon $ myLines !! 3) roomMap
                ids <- readMVar idMap
                let newId = ((words (show tId)) !! 1)
                    newMap = Map.insert newId tId ids
                swapMVar idMap newMap
                print ("newId: " ++ newId)
            "LEAVE_CHATROOM" -> do --clientLeave (kill sent joinID as it will match above (try to))
                print "leave test"
                rooms <- atomically $ readTVar roomMap
                let roomRef = splitColon $ head myLines
                    joinId = splitColon $ myLines !! 1
                    clientName = splitColon $ myLines !! 2
                    echo = "LEFT_CHATROOM:" ++ roomRef ++ "\n" ++ "JOIN_ID:" ++ joinId  -- watch for \n here!
                ids <- readMVar idMap
                print joinId
                case Map.lookup joinId ids of
                    Nothing -> do
                        print "leave test1"
                        print echo
                        hPutStrLn handle echo
                        print "now here"
                    Just threadId -> do
                        print ("leave test2 id: " ++ (show threadId))
                        hPutStrLn handle echo
                        print ("room ref: " ++ roomRef)
                        let chan = fromJust (Map.lookup roomRef rooms)
                        print "yoyoyo"
                        dupe <- dupChan chan
                        writeChan dupe (buildResponse roomRef clientName (clientName ++ " has left this chatroom."))
                        killThread threadId
            "CHAT" -> do
                rooms <- atomically $ readTVar roomMap
                ids <- readMVar idMap
                let joinId = splitColon $ myLines !! 1
                    roomRef = splitColon $ head myLines
                case Map.lookup joinId ids of
                    Nothing -> do
                        hPutStrLn handle (errmsg 5 "Must join chatroom first") -- not in channel, send error
                    Just _ -> do
                        case Map.lookup roomRef rooms of
                            Nothing -> do
                                hPutStrLn handle (errmsg 0 "server error")
                            Just chan -> do
                                dupe <- dupChan chan
                                writeChan dupe (head myLines ++ "\n" ++ (myLines !! 2) ++ "\n" ++ (myLines !! 3) ++ "\n")
            _ -> hPutStrLn handle $ "Unknown Message:" ++ msg
        loop
    print "DOWN HERE!"
    hClose handle
    --hdlConn (idMap,roomNames,roomMap,port,handle)

clientJoin :: Handle -> Int -> TVar (Map String String) -> String -> String -> TVar (Map String (Chan String)) -> IO ThreadId--IO ThreadId?
clientJoin handle port roomNames roomName clientName roomMap = do
    -- if user already present in room, do nothing (maybe check local list in above handler) yes... not here
    -- checking room existence ( use shared list of room names for this )
    nameMap <- atomically $ readTVar roomNames
    rooms <- atomically $ readTVar roomMap
    --id <- myThreadId
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
            print ("YOYO HERE MAH " ++ ((words (show listener)) !! 1))
            atomically $ modifyTVar roomMap (Map.insert ((words (show listener)) !! 1) chan)
            atomically $ modifyTVar roomNames (Map.insert roomName ((words (show listener)) !! 1))
            let response = "JOINED_CHATROOM:" ++ roomName ++ "\n" ++
                           "SERVER_IP:10.62.0.197" ++ "\n" ++
                           "PORT:" ++ (show port) ++ "\n" ++
                           "ROOM_REF:" ++ ((words (show listener)) !! 1) ++ "\n" ++
                           "JOIN_ID:" ++ ((words (show listener)) !! 1)
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
                                   "ROOM_REF:" ++ ((words (show listener)) !! 1) ++ "\n" ++
                                   "JOIN_ID:" ++ ((words (show listener)) !! 1)
                    hPutStrLn handle response
                    writeChan dupe (buildResponse roomRef clientName (clientName ++ " has joined this chatroom."))
                    return listener

buildResponse :: String -> String -> String -> String
buildResponse roomRef clientName msg = "CHAT:" ++ roomRef ++ "\n" ++
                                       "CLIENT_NAME:" ++ clientName ++ "\n" ++
                                       "MESSAGE:" ++ msg -- with \n?

myResponse :: String -> String -> Int -> String
myResponse msg host port = msg ++ "\n" ++
                           "IP:" ++ host ++ "\n" ++
                           "Port:" ++ show port ++ "\n" ++
                           "StudentID:13333179"
                           
errmsg :: Int -> String -> String
errmsg code desc = "ERROR_CODE: " ++ show code ++ "\n" ++
                   "ERROR_DESCRIPTION: " ++ desc  
     
-- syntax?                      
splitColon :: String -> String
splitColon str = (splitOn ":" str) !! 1
    
ioTakeWhile :: (a -> Bool) -> [IO a] -> IO [a]
ioTakeWhile pred actions = do
  print "DOWN HERE SON"
  x <- head actions
  if (pred x)
    then return [x]
    else (ioTakeWhile pred (tail actions)) >>= \xs -> return (x:xs)


main :: IO ()
main = withSocketsDo $ do
    args <- getArgs
    let port = read $ head args :: Int
    runServer port 
