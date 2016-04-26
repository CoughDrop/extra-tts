# ExtraTTS
Used to offer additional speech synthesis engines in cordova apps.

## Requirements
Built on top of Acapela's speech engine. On both Android and iOS you'll
need to reach out to Acapela to get the needed libraries and license
files. Demo packages should work for testing. For iOS you'll include
the license file once you get it. For Android you'll need to replace the 
code in the `init` method in ExtraTTS.java with your license code.

## License
MIT License

## TODO
- add examples (in the mean time, you can see how we're using it in
the TTS section here, https://github.com/CoughDrop/coughdrop/blob/master/app/frontend/app/utils/capabilities.js)