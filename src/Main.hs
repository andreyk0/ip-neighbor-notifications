{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Main where

import           Network.AMQP
import           Options.Applicative
import qualified Data.Text as T
import qualified Data.ByteString.Lazy.UTF8 as BU
import           Data.Monoid


data App =
  App { user:: String
      , password:: String
      , host:: String
      , port:: Int
      , vhost:: String
      , exchange:: String
      , routingKey:: String
      , bodyTxtOnly:: Bool
      }

parseApp :: Parser App
parseApp = App
     <$> strOption
         ( long "user"
        <> short 'u'
        <> value "guest"
        <> showDefault
        <> help "AMQP user" )
     <*> strOption
         ( long "password"
        <> short 'p'
        <> value "guest"
        <> showDefault
        <> help "AMQP password" )
     <*> strOption
         ( long "host"
        <> short 'H'
        <> value "localhost"
        <> showDefault
        <> help "AMQP host " )
     <*> (option auto)
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
     <*> strOption
         ( long "exchange"
        <> short 'e'
        <> value "amq.topic"
        <> showDefault
        <> help "AMQP exchange" )
     <*> strOption
         ( long "routing-key"
        <> short 'r'
        <> value "#"
        <> showDefault
        <> help "AMQP routing key, '*' matches any single word, '#' matches 0 or more words" )
     <*> switch
         ( long "body-text-only"
        <> short 'b'
        <> help "Print message body only, assuming UTF8 text." )


main :: IO ()
main = execParser opts >>= tailAMQP
  where
    opts = info (helper <*> parseApp)
      ( fullDesc
     <> header "Tail -f -like utility for checking AMQP exchange traffic." )


tailAMQP:: App -> IO ()
tailAMQP app@App{..} = do
  conn <- openConnection host (T.pack vhost) (T.pack user) (T.pack password)
  chan <- openChannel conn

  -- declare a queue, exchange and binding
  (qName, _, _) <- declareQueue chan newQueue { queueExclusive = True, queueAutoDelete = True }
  bindQueue chan qName (T.pack exchange) (T.pack routingKey)

  -- subscribe to the queue
  _ <- consumeMsgs chan qName Ack (msgCallback app)

  _ <- getLine -- wait for keypress
  closeConnection conn
  putStrLn "Connection closed."


msgCallback :: App -> (Message, Envelope) -> IO ()
msgCallback app (msg, env) = do
  if (bodyTxtOnly app)
    then putStrLn $ (T.unpack . envRoutingKey) env <> " => " <> (BU.toString (msgBody msg))
    else putStrLn $ (T.unpack . envRoutingKey) env <> " => " <> (show msg)

  ackEnv env
