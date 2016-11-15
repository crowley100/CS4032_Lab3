module Main where
 
import System.IO
import System.Exit
import System.Environment
import Network.Socket
import Network.BSD
import Control.Concurrent
import Control.Concurrent.STM
import Control.Monad
import Control.Monad.Fix (fix)
import Data.List.Split
import Data.List
import Data.Map 
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
mainLoop :: Socket -> TVar (Map String String) -> TVar (Map String (Chan String)) -> Chan (TVar (Map String String), TVar (Map String (Chan String)), Int, (Socket, SockAddr)) -> Int -> IO ()
mainLoop sock roomNames roomMap input port = do
    conn <- accept sock     -- accept a new client connection
    writeChan input (roomNames,roomMap,port,conn) -- pass id map in here (add to def for input chan) LOOK HERE FOR ID STUFF!!!
    mainLoop sock roomNames roomMap input port        -- loop

-- server logic
hdlConn :: (TVar (Map String String), TVar (Map String (Chan String)), Int, (Socket, SockAddr)) -> IO ()
hdlConn (roomNames,roomMap,port,(sock, _)) = do
    t <- myThreadId
    print t
    -- killThread t works
    test <- atomically $ readTVar roomMap
    print (Map.member "4" test)
    chan <- newChan 
    --let test = Map.insert 4 chan test
    atomically $ modifyTVar roomMap (Map.insert "4" chan)
    --myChan <- newChan
    --myMap <- Map.insert 4 myChan test 
    --test <- member "test" (readTVarIO roomMap)
    --print test
    handle <- socketToHandle sock ReadWriteMode
    hSetBuffering handle NoBuffering -- Line??
    
    msg <- hGetContents handle -- hGetLine ?? MAYBE ERROR HANDLING HERE!!! (see procress req)
    let lines = words msg
    let hiMsg = myResponse msg "134.226.32.10" port
    print hiMsg
    
    -- FIGURE OUT TVAR FOR SHARED MAP
    -- watch for spaces in parsing (e.g. in join param 1(2))
    -- error handling here: accepted <- try (handler params) case accepted of Left error Right finish
    case head lines of
        "KILL_SERVICE" -> sClose sock -- clean up first? os.exit...
        "HELO" -> hPutStr handle hiMsg
        "DISCONNECT:" -> hClose handle --kill all threads first or handle exceptions and send response! (send all leave responses)
        --"JOIN_CHATROOM:" -> clientJoin handle roomNames (splitColon $ head lines) (splitColon $ head lines !! 3) roomMap
        --(fork thread for reading, ret tID to user) maybe pop local list of rooms
        --"LEAVE_CHATROOM:" -> clientLeave (kill sent joinID as it will match above (try to))
        --"CHAT:" -> clientChat (check local list of rooms for ref, broadcast message)
        _ -> hPutStr handle $ "Unknown Message:" ++ msg
    
    hClose handle -- loop up here instead

clientJoin :: Handle -> TVar (Map String String) -> String -> String -> TVar (Map String (Chan String)) -> IO ThreadId--IO ThreadId?
clientJoin handle roomNames roomName clientName roomMap = do
    -- if user already present in room, do nothing (maybe check local list in above handler) yes... not here
    -- checking room existence ( use shared list of room names for this )
    names <- atomically $ readTVar roomNames
    rooms <- atomically $ readTVar roomMap
    --id <- myThreadId
    case Map.lookup roomName names of
        Nothing -> do -- does not exist (create&join)
            chan <- newChan
            dupe <- dupChan chan
            listener <- forkIO $ fix $ \loop -> do
                        msg <- readChan dupe
                        hPutStrLn handle msg
                        loop
            atomically $ modifyTVar roomMap (Map.insert (show listener) chan)
            atomically $ modifyTVar roomNames (Map.insert roomName (show listener))
            return listener
        Just roomRef -> do -- exists (join)
            case Map.lookup roomRef rooms of
                Nothing -> do
                    hPutStr handle (errmsg 0 "server error")
                    t <- myThreadId
                    return t -- generic return value
                Just channel -> do
                    dupe <- dupChan channel
                    -- fork off a thread for reading from the duplicated channel
                    listener <- forkIO $ fix $ \loop -> do
                        msg <- readChan dupe
                        hPutStrLn handle msg
                        loop
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
    
main :: IO ()
main = withSocketsDo $ do
    args <- getArgs
    let port = read $ head args :: Int
    runServer port 
