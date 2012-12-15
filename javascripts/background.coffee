chrome.extension.onMessage.addListener (req, sender, sendResponse) ->
  if req.fn?
    [api, fn] = req.fn.split '.'
    chrome[api]?[fn]?.apply? chrome[api], req.args
