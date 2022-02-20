-- | A very simple site with two routes, and HTML rendered using Blaze DSL
module Ema.Example.Ex02_Basic where

import Ema
import Ema.Example.Common (tailwindLayout)
import Ema.Route (HasRouteEncoder (getRouteEncoder), unsafeMkRouteEncoder)
import Text.Blaze.Html5 ((!))
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A

data Route
  = Index
  | About
  deriving stock (Show, Eq, Enum, Bounded)

newtype Model r = Model (RouteEncoder (Model r) r)

instance HasRouteEncoder (Model r) (Model r) r where
  getRouteEncoder (Model enc) = enc

routeEncoder :: RouteEncoder a Route
routeEncoder =
  unsafeMkRouteEncoder enc dec all_
  where
    enc _model =
      \case
        Index -> "index.html"
        About -> "about.html"
    dec _model = \case
      "index.html" -> Just Index
      "about.html" -> Just About
      _ -> Nothing
    all_ _ = defaultEnum @Route

site :: Site (Model Route) Route
site =
  Site
    { siteName = "Ex02",
      siteRender = \enc m r ->
        Ema.AssetGenerated Ema.Html $ render enc m r,
      siteModelData = \_act enc ->
        pure (Model enc, \_ -> pure ()),
      siteRouteEncoder = routeEncoder
    }

main :: IO ()
main = do
  void $ Ema.runSite site

render :: RouteEncoder (Model Route) Route -> Model Route -> Route -> LByteString
render _enc model@(Model enc) r =
  tailwindLayout (H.title "Basic site" >> H.base ! A.href "/") $
    H.div ! A.class_ "container mx-auto" $ do
      H.div ! A.class_ "mt-8 p-2 text-center" $ do
        H.p $ H.em "Hello"
        case r of
          Index -> do
            "You are on the index page. "
            routeElem About "Go to About"
          About -> do
            routeElem Index "Go to Index"
            ". You are on the about page. "
  where
    routeElem r' w =
      H.a ! A.class_ "text-red-500 hover:underline" ! routeHref r' $ w
    routeHref r' =
      A.href (fromString . toString $ Ema.routeUrl enc model r')
