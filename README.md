# ExtraTTS
Used to offer additional speech synthesis engines in cordova apps.

## Requirements
Built on top of Acapela's speech engine. On both Android and iOS you'll
need to raeach out to Acapela to get the needed libraries and license
files. Demo packages should work for testing. For iOS you'll include
the license file once you get it. For Android you'll need to replace the 
code in the `init` method in ExtraTTS.java with your license code.

## Usage
`cordova plugin add https://www.github.com/coughdrop/extra-tts.git`

```
window.cordova.exec(function(res) {
  console.log('ready!');
}, function(err) {
  console.error('not ready');
}, 'ExtraTTS', 'status', []);

window.cordova.exec(function(list) {
  // list of available voice ids
  console.log(list);
}, function(err) { }, 'ExtraTTS, 'getAvailableVoices', []);

window.cordova.exec(function() {
  console.log("done speaking");
}, function(err) { }, 'ExtraTTS', 'speakText', [{
  voice_id: "<voice id from list>",
  text: "Good afternoon if that's time time"
}]);
```

## License
MIT License

## TODO
- add examples (in the mean time, you can see how we're using it in
the TTS section here, https://github.com/CoughDrop/coughdrop/blob/master/app/frontend/app/utils/capabilities.js)
- specs (stop judging me, I'm not a native app developer)
- move android license to a config file so nobody has to rewrite code