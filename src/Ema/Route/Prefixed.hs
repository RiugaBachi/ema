module Ema.Route.Prefixed
  ( PrefixedRoute (PrefixedRoute, unPrefixedRoute),
    toPrefixedRouteEncoder,
    fromPrefixedRouteEncoder,
  )
where

import Data.Text qualified as T
import Ema.Asset (RenderAsset (..))
import Ema.Model
  ( HasModel (ModelInput, runModel),
  )
import Ema.Route.Class (IsRoute (..))
import Ema.Route.Encoder
  ( RouteEncoder,
    mapRouteEncoder,
  )
import GHC.TypeLits (KnownSymbol, Symbol, symbolVal)
import Optics.Core (iso, prism')
import System.FilePath ((</>))
import Text.Show (Show (show))

instance (HasModel r, KnownSymbol prefix) => HasModel (PrefixedRoute prefix r) where
  type ModelInput (PrefixedRoute prefix r) = ModelInput r
  runModel cliAct enc input =
    runModel @r cliAct (fromPrefixedRouteEncoder enc) input

instance (RenderAsset r, KnownSymbol prefix) => RenderAsset (PrefixedRoute prefix r) where
  renderAsset enc m r =
    renderAsset @r (fromPrefixedRouteEncoder enc) m (unPrefixedRoute r)

toPrefixedRouteEncoder :: forall prefix r a. KnownSymbol prefix => RouteEncoder a r -> RouteEncoder a (PrefixedRoute prefix r)
toPrefixedRouteEncoder =
  let prefix = symbolVal (Proxy @prefix)
   in mapRouteEncoder
        (iso (prefix </>) $ fmap toString . T.stripPrefix (toText $ prefix <> "/") . toText)
        (prism' unPrefixedRoute (Just . PrefixedRoute))
        id

-- This coerces the r, but without losing the prefix encoding.
fromPrefixedRouteEncoder :: forall prefix r a. RouteEncoder a (PrefixedRoute prefix r) -> RouteEncoder a r
fromPrefixedRouteEncoder =
  mapRouteEncoder (iso id Just) (prism' PrefixedRoute (Just . unPrefixedRoute)) id

-- | A route that is prefixed at some URL prefix
newtype PrefixedRoute (prefix :: Symbol) r = PrefixedRoute {unPrefixedRoute :: r}
  deriving newtype (Eq, Ord)

instance (Show r, KnownSymbol prefix) => Show (PrefixedRoute prefix r) where
  show (PrefixedRoute r) = symbolVal (Proxy @prefix) <> "/:" <> Text.Show.show r

instance (IsRoute r, KnownSymbol prefix) => IsRoute (PrefixedRoute prefix r) where
  type RouteModel (PrefixedRoute prefix r) = RouteModel r
  mkRouteEncoder = toPrefixedRouteEncoder @prefix @r @(RouteModel r) $ mkRouteEncoder @r