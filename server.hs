module Main where
 
import System.IO
import System.Exit
import System.Environment
import Network.Socket
import Network.BSD
import Control.Concurrent
import Control.Monad
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
    let rooms = empty
    (input,output) <- threadPoolIO myPool hdlConn   -- 50 workers
    
    --let str = roomName myRoom -- accessing elements of datatype
    --print str
    mainLoop sock input port
  
-- handle connections  
mainLoop :: Socket -> Chan (Int,(Socket, SockAddr)) -> Int -> IO ()
mainLoop sock input port = do
    conn <- accept sock     -- accept a new client connection
    writeChan input (port,conn)
    mainLoop sock input port        -- loop

-- server logic
hdlConn :: (Int,(Socket, SockAddr)) -> IO ()
hdlConn (port,(sock, _)) = do
    t <- myThreadId
    print t
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
        "KILL_SERVICE" -> sClose sock -- clean up first?
        "HELO" -> hPutStr handle hiMsg
        "DISCONNECT:" -> hClose handle --kill all threads first or handle exceptions
        --"JOIN_CHATROOM:" -> clientJoin (fork thread for reading, ret tID to user) maybe pop local list of rooms
        --"LEAVE_CHATROOM:" -> clientLeave (kill sent joinID as it will match above (try to))
        --"CHAT:" -> clientChat (check local list of rooms for ref, broadcast message)
        _ -> putStrLn $ "Unknown Message:" ++ msg
    
    hClose handle -- loop up here instead
  
myResponse :: String -> String -> Int -> String
myResponse msg host port = msg ++ "\n" ++
                           "IP:" ++ host ++ "\n" ++
                           "Port:" ++ show port ++ "\n" ++
                           "StudentID:13333179"  
     
-- syntax?                      
splitColon :: String -> String
splitColon str = (splitOn ":" str) !! 1
    
main :: IO ()
main = withSocketsDo $ do
    args <- getArgs
    let port = read $ head args :: Int
    runServer port
