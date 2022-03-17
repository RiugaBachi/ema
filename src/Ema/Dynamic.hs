{-# LANGUAGE UndecidableInstances #-}

module Ema.Dynamic
  ( Dynamic (Dynamic),
  )
where

import Colog
import Ema.App.Env
import UnliftIO (MonadUnliftIO, race_)
import UnliftIO.Concurrent (threadDelay)

-- | A time-varying value
--
--  To create a Dynamic, supply the initial value along with a function that knows
--  how to update it using the given update function.
--
-- Dynamic's can be composed using Applicative.
newtype Dynamic m a
  = Dynamic
      ( -- Initial value
        a,
        -- Set a new value
        (a -> m ()) -> m ()
      )

instance Functor (Dynamic m) where
  fmap f (Dynamic (x0, xf)) =
    Dynamic
      ( f x0,
        \send -> xf $ send . f
      )

instance
  ( MonadUnliftIO m,
    HasLog (Env App) (Msg Severity) m,
    MonadReader (Env App) m
  ) =>
  Applicative (Dynamic m)
  where
  pure x = Dynamic (x, \_ -> pure ())
  liftA2 f (Dynamic (x0, xf)) (Dynamic (y0, yf)) =
    Dynamic
      ( f x0 y0,
        \send -> do
          var <- newTVarIO (x0, y0)
          sendLock :: TMVar () <- newEmptyTMVarIO
          -- TODO: Use site name in logging?
          race_
            ( do
                xf $ \x -> do
                  atomically $ putTMVar sendLock ()
                  log D "left update"
                  send <=< atomically $ do
                    modifyTVar' var $ first (const x)
                    f x . snd <$> readTVar var
                  atomically $ takeTMVar sendLock
                log D "updater exited; keeping thread alive"
                threadDelay maxBound
            )
            ( do
                yf $ \y -> do
                  atomically $ putTMVar sendLock ()
                  log D "right update"
                  send <=< atomically $ do
                    modifyTVar' var $ second (const y)
                    (`f` y) . fst <$> readTVar var
                  atomically $ takeTMVar sendLock
                log D "updater exited; keeping thread alive"
                threadDelay maxBound
            )
      )
