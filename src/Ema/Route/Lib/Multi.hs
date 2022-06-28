{-# OPTIONS_GHC -Wno-orphans #-}

{- | Merging multiple Ema sites into one.

    This is implemented in using `sop-core`'s NS and NP types. Use as
    `MultiRoute '[MySite1, MySite2, ...]`.
-}
module Ema.Route.Lib.Multi (
  MultiRoute,
  MultiModel,
) where

import Data.SOP (I (..), NP (..), NS (..))
import Ema.Route.Class (IsRoute (..))
import Ema.Route.Encoder
import Ema.Site (EmaSite (..))
import Optics.Core (iso, prism', (%))

{- | The merged site's route is represented as a n-ary sum (`NS`) of the
 sub-routes.
-}
type MultiRoute (rs :: [Type]) = NS I rs

type family MultiModel (rs :: [Type]) :: [Type] where
  MultiModel '[] = '[]
  MultiModel (r ': rs) = RouteModel r : MultiModel rs

type family MultiSiteArg (rs :: [Type]) :: [Type] where
  MultiSiteArg '[] = '[]
  MultiSiteArg (r ': rs) = SiteArg r : MultiSiteArg rs

instance IsRoute (MultiRoute '[]) where
  type RouteModel (MultiRoute '[]) = NP I '[]
  routeEncoder = impossibleEncoder
    where
      impossibleEncoder :: RouteEncoder (NP I '[]) (MultiRoute '[])
      impossibleEncoder = mkRouteEncoder $ \Nil ->
        prism' (\case {}) (const Nothing)
  allRoutes Nil = mempty

instance
  ( IsRoute r
  , IsRoute (MultiRoute rs)
  , RouteModel (MultiRoute rs) ~ NP I (MultiModel rs)
  ) =>
  IsRoute (MultiRoute (r ': rs))
  where
  type RouteModel (MultiRoute (r ': rs)) = NP I (RouteModel r ': MultiModel rs)
  routeEncoder =
    routeEncoder @r
      `nsRouteEncoder` routeEncoder @(MultiRoute rs)
  allRoutes (I m :* ms) =
    fmap (toNS . Left) (allRoutes @r m)
      <> fmap (toNS . Right) (allRoutes @(MultiRoute rs) ms)

instance EmaSite (MultiRoute '[]) where
  type SiteArg (MultiRoute '[]) = NP I '[]
  siteInput _ Nil = pure $ pure Nil
  siteOutput _ Nil = \case {}

instance
  ( EmaSite r
  , EmaSite (MultiRoute rs)
  , SiteArg (MultiRoute rs) ~ NP I (MultiSiteArg rs)
  , RouteModel (MultiRoute rs) ~ NP I (MultiModel rs)
  ) =>
  EmaSite (MultiRoute (r ': rs))
  where
  type SiteArg (MultiRoute (r ': rs)) = NP I (MultiSiteArg (r ': rs))
  siteInput cliAct (I i :* is) = do
    m <- siteInput @r cliAct i
    ms <- siteInput @(MultiRoute rs) cliAct is
    pure $ curry toNP <$> m <*> ms
  siteOutput rp (I m :* ms) =
    fromNS
      >>> either
        (siteOutput @r (rp % headRoute) m)
        (siteOutput @(MultiRoute rs) (rp % tailRoute) ms)
    where
      tailRoute =
        (prism' (toNS . Right) (fromNS >>> rightToMaybe))
      headRoute =
        (prism' (toNS . Left) (fromNS >>> leftToMaybe))

-- | Like `eitherRouteEncoder` but uses sop-core types instead of Either/Product.
nsRouteEncoder ::
  RouteEncoder a r ->
  RouteEncoder (NP I as) (NS I rs) ->
  RouteEncoder (NP I (a ': as)) (NS I (r ': rs))
nsRouteEncoder a b =
  eitherRouteEncoder a b
    & mapRouteEncoderRoute (iso toNS fromNS)
    & mapRouteEncoderModel fromNP

fromNP :: NP I (a ': as) -> (a, NP I as)
fromNP (I x :* y) = (x, y)

toNP :: (a, NP I as) -> NP I (a ': as)
toNP (x, y) = I x :* y

fromNS :: NS I (a ': as) -> Either a (NS I as)
fromNS = \case
  Z (I x) -> Left x
  S xs -> Right xs

toNS :: Either a (NS I as) -> NS I (a ': as)
toNS = either (Z . I) S