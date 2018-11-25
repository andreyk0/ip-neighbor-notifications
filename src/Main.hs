{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TemplateHaskell   #-}

module Main where


import           Control.Concurrent
import           Control.Monad
import           Data.Aeson
import           Data.Aeson.TH
import           Data.Char
import           Data.Conduit
import qualified Data.Conduit.Combinators as C
import           Data.Conduit.Shell (($|))
import qualified Data.Conduit.Shell as Sh
import qualified Data.Conduit.Text as C
import           Data.Maybe
import           Data.Text (Text)
import qualified Data.Text as T
import           Network.AMQP
import           Options.Applicative
import           System.Environment


data App =
  App { user:: !String
      , password:: !String
      , host:: !String
      , port:: !Int
      , vhost:: !String
      }

parseApp :: Maybe String
         -> Maybe String
         -> Maybe String
         -> Parser App
parseApp maybeAmqpU maybeAmqpP maybeAmqpH = App
     <$> strOption
         ( long "user"
        <> short 'u'
        <> value (fromMaybe "guest" maybeAmqpU)
        <> showDefault
        <> help "AMQP user" )
     <*> strOption
         ( long "password"
        <> short 'p'
        <> value (fromMaybe "guest" maybeAmqpP)
        <> help "AMQP password" )
     <*> strOption
         ( long "host"
        <> short 'H'
        <> value (fromMaybe "localhost" maybeAmqpH)
        <> showDefault
        <> help "AMQP host " )
     <*> option auto
         ( long "port"
        <> short 'P'
        <> value 5672
        <> showDefault
        <> help "AMQP port" )
     <*> strOption
         ( long "vhost"
        <> short 'v'
        <> value "/"
        <> showDefault
        <> help "AMQP virtual host" )


-- | Publish to default topic exchange
appExchangeName :: Text
appExchangeName = "amq.topic"

-- | Publishes all messages with this routing key
appRoutingKey :: Text
appRoutingKey = "ip-neighbor"


data IPNeighboor = IPNeighboor
  { ipnIp :: !Text
  , ipnMac :: !Text
  } deriving (Eq, Show)

$(deriveJSON defaultOptions{ fieldLabelModifier = map toLower . drop 3
                           , constructorTagModifier = map toLower
                           } ''IPNeighboor)


main :: IO ()
main = do
  u <- lookupEnv "AMQP_USER"
  p <- lookupEnv "AMQP_PASSWORD"
  h <- lookupEnv "AMQP_HOST"

  execParser (opts u p h) >>= sendMessages
  where
    opts u p h = info (helper <*> parseApp u p h)
      ( fullDesc
     <> (header . T.unpack) ("Publishes IP Neighbor updates to " <> appExchangeName <>
                             " AMQP exchange with " <> appRoutingKey <> " routing key"))


sendMessages :: App -> IO ()
sendMessages  App{..} = do
  conn <- openConnection host (T.pack vhost) (T.pack user) (T.pack password)
  chan <- openChannel conn

  -- declare a queue, exchange and binding
  (qName, _, _) <- declareQueue chan newQueue { queueExclusive = True, queueAutoDelete = True }
  bindQueue chan qName appExchangeName appRoutingKey

  let publish msgs = void $
        publishMsg chan appExchangeName appRoutingKey newMsg { msgBody = encode msgs
                                                             , msgDeliveryMode = Just NonPersistent }

  -- publish a message to our new exchange
  void . forever $ do
    ns <- findNeighbors
    publish ns
    threadDelay (10 * 1000000)

  -- crap out and let watchdog process restart it if it's running in the background
  closeConnection conn


-- | Queries ARP cache to find IP neighbors
findNeighbors :: IO [IPNeighboor]
findNeighbors =
  Sh.run ( Sh.proc "ip" ["neighbor", "show"]
        $| Sh.conduit (C.decodeUtf8 .| decodeNeighbors `fuseUpstream` C.encodeUtf8)
         )
  where decodeNeighbors = C.lines .| C.concatMap parseLine .| C.sinkList


-- | Parses output of 'ip neighbor', not everything can be parsed,
-- some stale IPs fail to print all the usual fields
parseLine :: Text -> Maybe IPNeighboor
parseLine l =
  case T.splitOn " " l
    of [tIp, _, _, _, tMac, _] -> Just $ IPNeighboor tIp tMac
       _                       -> Nothing
