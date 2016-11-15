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

data Client = Client
    { clientID :: Int
    , clientNick :: String
    , clientConn :: Socket
    }

data Room = Room
    { roomID :: Int
    , roomName :: String
    , roomClients :: [String]
    } 

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
mainLoop :: Socket -> TVar (Map String String) -> TVar (Map String (Chan String)) -> Chan (Map String ThreadId,TVar (Map String String), TVar (Map String (Chan String)), Int, Handle) -> Int -> IO ()
mainLoop sock roomNames roomMap input port = do
    t <- myThreadId
    --print ("main line..." ++ (show t))
    (conn,_) <- accept sock     -- accept a new client connection
    handle <- socketToHandle conn ReadWriteMode
    hSetBuffering handle NoBuffering -- Line??
    let ids = singleton (show t) t
    --let parentThread = Map.lookup "1" ids
    --print (fromJust parentThread) 
    writeChan input (ids,roomNames,roomMap,port,handle) -- pass id map in here (add to def for input chan) LOOK HERE FOR ID STUFF!!!
    mainLoop sock roomNames roomMap input port        -- loop

-- server logic
hdlConn :: (Map String ThreadId,TVar (Map String String), TVar (Map String (Chan String)), Int, Handle) -> IO ()
hdlConn (idMap,roomNames,roomMap,port,handle) = do
    t <- myThreadId
    print t
    --print msg
    -- killThread t works
    --test <- atomically $ readTVar roomMap
    --print (Map.member "4" test)
    --chan <- newChan 
    --let test = Map.insert 4 chan test
    --atomically $ modifyTVar roomMap (Map.insert "4" chan)
    --myChan <- newChan
    --myMap <- Map.insert 4 myChan test 
    --test <- member "test" (readTVarIO roomMap)
    --print test
    --handle <- socketToHandle sock ReadWriteMode
    --hSetBuffering handle NoBuffering -- Line??
    
    print "hi"
    --msg <- hGetContents handle -- hGetLine ?? MAYBE ERROR HANDLING HERE!!! (see procress req)
    let lineActions = repeat (hGetLine handle)
    myLines <- ioTakeWhile (/= "CLIENT_NAME: dave") lineActions -- split on colon [0]
    print myLines
    print "ho"
    --print msg
    let msg = concat myLines
    --let hiMsg = myResponse msg "134.226.32.10" port
    --print hiMsg
    
    -- FIGURE OUT TVAR FOR SHARED MAP
    -- watch for spaces in parsing (e.g. in join param 1(2))
    -- error handling here: accepted <- try (handler params) case accepted of Left error Right finish
    case head myLines of
        "KILL_SERVICE" -> do
            hClose handle -- clean up first? os.exit...
            --let parentThread = Map.lookup "1" idMap
            let parentThread = Map.lookup "ThreadId 1" idMap
            killThread (fromJust parentThread) 
            --throwTo (fromJust parentThread) killThread
        "HELO" -> do 
            let hiMsg = myResponse msg "134.226.32.10" port
            hPutStrLn handle hiMsg
        "DISCONNECT:" -> hClose handle --kill all threads first or handle exceptions and send response! (send all leave responses)
        "JOIN_CHATROOM:" -> do 
            tId <- clientJoin handle port roomNames (splitColon $ head myLines) (splitColon $ myLines !! 3) roomMap
            let idMap = Map.insert (show tId) tId idMap
            print ("new id: " ++ show tId)
        --(fork thread for reading, ret tID to user) maybe pop local list of rooms
        --"LEAVE_CHATROOM:" -> clientLeave (kill sent joinID as it will match above (try to))
        --"CHAT:" -> clientChat (check local list of rooms for ref, broadcast message)
        _ -> hPutStrLn handle $ "Unknown Message:" ++ msg
    
    --hClose handle -- loop up here instead
    hdlConn (idMap,roomNames,roomMap,port,handle)

clientJoin :: Handle -> Int -> TVar (Map String String) -> String -> String -> TVar (Map String (Chan String)) -> IO ThreadId--IO ThreadId?
clientJoin handle port roomNames roomName clientName roomMap = do
    -- if user already present in room, do nothing (maybe check local list in above handler) yes... not here
    -- checking room existence ( use shared list of room names for this )
    nameMap <- atomically $ readTVar roomNames
    rooms <- atomically $ readTVar roomMap
    --id <- myThreadId
    case Map.lookup roomName nameMap of
        Nothing -> do -- does not exist (create&join)
            chan <- newChan
            dupe <- dupChan chan
            listener <- forkIO $ fix $ \loop -> do
                        msg <- readChan dupe
                        hPutStrLn handle msg
                        loop
            atomically $ modifyTVar roomMap (Map.insert (show listener) chan)
            atomically $ modifyTVar roomNames (Map.insert roomName (show listener))
            let response = "JOINED_CHATROOM:" ++ roomName ++ "\n" ++
                           "SERVER_IP:134.226.32.10" ++ "\n" ++
                           "PORT:" ++ (show port) ++ "\n" ++
                           "ROOM_REF:" ++ (show listener) ++ "\n" ++
                           "JOIN_ID:" ++ (show listener)
            hPutStrLn handle response
            writeChan dupe (clientName ++ " has joined this chatroom")
            return listener
        Just roomRef -> do -- exists (join)
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
                           "ROOM_REF:" ++ (show listener) ++ "\n" ++
                           "JOIN_ID:" ++ (show listener)
                    hPutStrLn handle response
                    writeChan dupe (clientName ++ " has joined this chatroom")
                    return listener -- this syntax ok? otherwise pop list here?

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
  x <- head actions
  if pred x
    then (ioTakeWhile pred (tail actions)) >>= \xs -> return (x:xs)
    else return [x]
    
main :: IO ()
main = withSocketsDo $ do
    args <- getArgs
    let port = read $ head args :: Int
    runServer port 
