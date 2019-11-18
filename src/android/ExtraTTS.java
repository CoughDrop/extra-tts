package com.mycoughdrop.coughdrop;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.os.Bundle;


import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CallbackContext;
import org.apache.cordova.PluginResult;


import com.acapelagroup.android.tts.acattsandroid; 
import com.acapelagroup.android.tts.acattsandroid.iTTSEventsCallback;

import android.util.Log;
import java.io.File;
import java.io.BufferedInputStream;
import java.io.FileOutputStream;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.IOException;
import java.io.FileNotFoundException;
import java.net.URL;
import java.net.URLConnection;
import java.util.zip.ZipEntry; 
import java.util.zip.ZipInputStream;
import java.util.Map;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import android.app.AlertDialog;
import android.content.DialogInterface;


/**
 * Text-to-speech using class libraries rather than speechSynthesis
**/

public class ExtraTTS extends CordovaPlugin implements iTTSEventsCallback {
  private static final String TAG = "ExtraTTS";

  private acattsandroid TTS = null;
  private boolean ready = false;
  private String storageLocation = null;
  private String loadedVoice = null;
  private CallbackContext lastCallback = null;
  private JSONObject lastTextOpts = null;
  private double lastDownloadPercent = -1;  

  static {
    System.loadLibrary("acattsandroid");
  }
  
  @Override
  public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
    if (action.equals("echo")) {
      String message = args.getString(0);
      this.echo(message, callbackContext);
      return true;
    } else if(action.equals("init")) {
      init(callbackContext);
      return true;
    } else if(action.equals("status")) {
      status(callbackContext);
      return true;
    } else if(action.equals("getAvailableVoices")) {
      availableVoices(callbackContext);
      return true;
    } else if(action.equals("downloadVoice")) {
      downloadVoice(args, callbackContext);
      return true;
    } else if(action.equals("deleteVoice")) {
      deleteVoice(args, callbackContext);
      return true;
    } else if(action.equals("speakText")) {
      speakText(args, callbackContext, false);
      return true;
    } else if(action.equals("stopSpeakingText")) {
      stopText(callbackContext);
      return true;
    } else if(action.equals("renderText")) {
      speakText(args, callbackContext, true);
    }
    return false;
  }
  
  private void init(CallbackContext callbackContext) {
    String storage = cordova.getActivity().getApplicationContext().getExternalFilesDir(null).getAbsolutePath();
    storageLocation = storage + "/coughdrop_voices/";

    TTS = new acattsandroid(this.cordova.getActivity().getApplicationContext(),this,null);
    TTS.setLog(true);

    // NOTE: set this to false and paste in your new license value
    boolean demo_license = true;
    TTS.setLicense(0x444b4453,0x11de4055,"\"5263 0 SDKD #EVALUATION#SDK-demo-Acapela-group\"\nVGm3Ie@Oi$56NUOwSUZxje%Zi@M%ejX2!eXhovWviS2ZZQgAl2gt8RJCejPrk8k#\nTaUxVYANC%RG39EaCr8qOhBNmw@BI%JA3gn9yi%2NkMluDnq\nY6Z7o8CzkPK5p2G$xNFobT##\n"); 
	    
    if(demo_license) {
      AlertDialog.Builder LicenseDialog = new AlertDialog.Builder(cordova.getActivity());
      LicenseDialog.setTitle("Evaluation license");
      LicenseDialog.setMessage("You'll have to insert your own license in the source code to use your voices");
      LicenseDialog.setPositiveButton("OK",new DialogInterface.OnClickListener() {
        public void onClick(DialogInterface dialog, int which) {

        }
      });
      LicenseDialog.show();
    }
 		
    this.ready = true;
    callbackContext.success("cool beans");
  }
  
  private void status(CallbackContext callbackContext) throws JSONException {
    JSONObject result = new JSONObject();
    result.put("ready", this.ready);
    if(this.ready) {
      callbackContext.success(result);
    } else {
      callbackContext.error(result);
    }
  }
  
  private void availableVoices(CallbackContext callbackContext) throws JSONException {
    if(!this.ready) { 
      callbackContext.error("not ready");
    } else {
      String[] paths = {storageLocation};
      String[] currentVoices = TTS.getVoicesList(paths);
      String lang = null;
      JSONArray res = new JSONArray();
      for(String voice : currentVoices) {
        Map<String, String> voiceInfo = TTS.getVoiceInfo(voice);
        if(voiceInfo != null && !voiceInfo.get("name").equals("")) {
          JSONObject obj = new JSONObject();
          obj.put("language", voiceInfo.get("language"));
          obj.put("locale", "en-US");
          obj.put("active", true);
          obj.put("name", voice);
          obj.put("voice_id", "acap:" + voice);
          if(lang == null) {
            lang = voice;
          } else {
            // langs += "," + voice;
          }
          res.put(obj);
        }
      }
      try {
        if(lang == null) { lang = "en"; }
        TTS.load(lang,"");
        loadedVoice = lang;
        TTS.getLanguage();
      } catch(Exception e) { }
      callbackContext.success(res);
    }
  }

  private void downloadProgress(double percent, CallbackContext callbackContext) throws JSONException{
    double trimmedPercent = Math.round(percent * 100.0) / 100.0;
    JSONObject status = new JSONObject();
    status.put("percent", trimmedPercent);
    status.put("done", false);
    if(percent >= 1.0) {
      status.put("percent", 1.0);
      status.put("done", true);
      callbackContext.success(status);
    } else if(lastDownloadPercent != trimmedPercent) {
      lastDownloadPercent = trimmedPercent;
      PluginResult result = new PluginResult(PluginResult.Status.OK, status);
      result.setKeepCallback(true);
      callbackContext.sendPluginResult(result);
    }
  }
  
  private void downloadVoice(final JSONArray args, final CallbackContext callbackContext) throws JSONException {
    if(!this.ready) { 
      callbackContext.error("not ready");
    } else {
      cordova.getThreadPool().execute(new Runnable() {
          public void run() {
            try {
              String voiceUrl = args.getJSONObject(0).getString("voice_url");
              
              Log.d(TAG, "getting file...");
              URL url = new URL(voiceUrl);
              URLConnection connection = url.openConnection();
              connection.connect();

              int lengthOfFile = connection.getContentLength();
              if(lengthOfFile == 0) {
                lengthOfFile = 50000000;
              }
              double totalChunks = lengthOfFile / 1024;

              Log.d(TAG, "Length of file: " + lengthOfFile);

              dirChecker(storageLocation);

              InputStream input = new BufferedInputStream(url.openStream());
              OutputStream output = new FileOutputStream(storageLocation + "voice.zip");

              double nChunks = 0;
              int count;
              byte data[] = new byte[1024];

              while ((count = input.read(data)) != -1) {
                nChunks += 1;
                output.write(data, 0, count);
                downloadProgress(Math.min(0.75, 0.75 * nChunks / totalChunks), callbackContext);
              }

              output.flush();
              output.close();
              input.close();
              
              downloadProgress(0.75, callbackContext);
              Log.d(TAG, "Unzipping file...");
        
              FileInputStream fin = new FileInputStream(storageLocation + "voice.zip"); 
              ZipInputStream zin = new ZipInputStream(fin); 
              ZipEntry ze = null; 
              double totalEntries = 60;
              double nEntries = 0;
              while ((ze = zin.getNextEntry()) != null) { 
                nEntries += 1;
                Log.d(TAG, "Unzipping " + ze.getName()); 

                if(ze.isDirectory()) { 
                  dirChecker(storageLocation + ze.getName()); 
                } else { 
                  FileOutputStream fout = new FileOutputStream(storageLocation + ze.getName()); 
            
                  for (int c = zin.read(data); c != -1; c = zin.read(data)) { 
                    fout.write(data, 0, c); 
                  } 

                  zin.closeEntry(); 
                  fout.close(); 
                } 
                downloadProgress(0.74 + Math.min(0.25, 0.25 * nEntries / totalEntries), callbackContext);
              } 
        
              File file = new File(storageLocation + "voice.zip");
              file.delete();
              zin.close(); 
              downloadProgress(1.0, callbackContext);
            } catch (Exception e) {
              callbackContext.error(e.getMessage() + " " + e.getStackTrace().length);
            }
          }
      });
    }
  }
  
  private void deleteVoice(JSONArray args, CallbackContext callbackContext) throws JSONException {
    String voiceDir = args.getJSONObject(0).getString("voice_dir");
    try {
      deleteDir(new File(storageLocation + voiceDir));
      callbackContext.success();
    } catch(IOException e) {
      callbackContext.error(e.getMessage());
    }
  }
  
  private void dirChecker(String dir) { 
    File f = new File(dir); 
 
    if(!f.isDirectory()) { 
      f.mkdirs(); 
    } 
  } 
    
  private void speakText(JSONArray args, CallbackContext callbackContext, boolean renderToFile) throws JSONException {
    if(!this.ready) { 
      callbackContext.error("not ready"); 
    } else {
      JSONObject json = args.getJSONObject(0);
      double ratePercent = 1.0;
      double pitchPercent = 1.0;
      double volumePercent = 1.0;
      try {
        ratePercent = json.getDouble("rate");
      } catch(JSONException e) { }
      try {
        volumePercent = json.getDouble("volume");
      } catch(JSONException e) { }
      try {
        pitchPercent = json.getDouble("pitch");
      } catch(JSONException e) { }
      String voiceId = null;
      try {
        voiceId = json.getString("voice_id");
      } catch(JSONException e) { }

      if((loadedVoice == null || !loadedVoice.equals(voiceId)) && voiceId != null) {
        TTS.load(voiceId.replaceAll("acap:", ""),"");
        loadedVoice = voiceId;
        TTS.getLanguage();
      }

      int pitch = (int) Math.min(Math.max(pitchPercent * 100, 70), 130);
      int rate = (int) Math.min(Math.max(ratePercent * 120, 50), 400);
      TTS.setPitch(pitch); // from 70 to 130
      TTS.setSpeechRate(rate); // from 50 to 400
      String text = json.getString("text");
      JSONObject opts = new JSONObject();
      opts.put("pitch", pitchPercent);
      opts.put("modified_pitch", pitch);
      opts.put("rate", ratePercent);
      opts.put("modified_rate", rate);
      opts.put("volume", volumePercent);
      opts.put("modified_volume", null);
      opts.put("text", text);
      if(voiceId != null) {
        //text = "\\vce=speaker=Ella\\" + text;
      }
      opts.put("modified_text", text);
      if(renderToFile) {
        String filePath = cordova.getActivity().getApplicationContext().getExternalFilesDir(null).getAbsolutePath() + "/audio_" + voiceId.replaceAll(":", "_") + ".wav";
        TTS.synthesizeToFile(text, filePath);
        callbackContext.success(filePath);
      } else {
        int idx = TTS.speak(text);
        opts.put("text_reference", idx);
        Log.d(TAG, "Text " + idx + " speaking");
        lastCallback = callbackContext;
        lastTextOpts = opts;
      }
    }
  }
  
  private void stopText(CallbackContext callbackContext) {
    if(!this.ready) { 
      callbackContext.error("not ready"); 
    } else {
      handleLastCallback(true, true);
      TTS.stop();
      callbackContext.success();
    }
  }

  private void echo(String message, CallbackContext callbackContext) {
    if (message != null && message.length() > 0) {
        callbackContext.success(message);
    } else {
        callbackContext.error("Expected one non-empty string argument.");
    }
  }
  
  private void handleLastCallback(boolean success, boolean interrupt) {
    if(lastCallback != null) {
      if(success) {
        if(interrupt && lastTextOpts != null) {
          try {
            lastTextOpts.put("interrupted", true);
          } catch(JSONException e) { }
        }
        lastCallback.success(lastTextOpts);
      } else {
        lastCallback.error("error");
      }
      lastCallback = null;
      lastTextOpts = null;
    }
  }
  
  public void ttsevents(long type,long param1,long param2,long param3,long param4) {
    if (type == acattsandroid.EVENT_AUDIO_END) {
      Log.d(TAG, "Text " + param1 + " processed");
      handleLastCallback(true, false);
    }
  }

  private void deleteDir(File f) throws IOException {
    if (f.isDirectory()) {
      for (File c : f.listFiles())
        deleteDir(c);
    }
    if (!f.delete())
      throw new FileNotFoundException("Failed to delete file: " + f);
  }
  
}