/*

 SelfReflector for the V&A Digital Weekend 2016
 V1. 13.09.16
 
 Things to do.
 
 Arduino mat - tick
 Minim song playing - tick
 SelfReflector SpexPistols logic flow (from FinalMirror3)
 
 */



import httprocessing.*;
import processing.video.*;
import processing.serial.*;
import cc.arduino.*;
import ddf.minim.*;

Minim minim;
AudioPlayer song;
Arduino arduino;
PostRequest post; 
Capture cam;


static final int FLASH_PIN = 13; // camera flash on Arduino io pin 13 - CHANGE TO 6 for SelfReflector
static final int MAT_PIN = 7; 
static final int MAT_DELAY=2000; // the delay that occurs between when you step on mat and flash happens
static final int CAM_FLASH=350;  // original was 50 
static final int MIN_PLAY_TIME = 4000; //lock out mat to print un-interupted // 4 second play of the track..
static final int MAX_CAM_TRY = 20; // slightly arbitary 20 times repeat until it finds a face in a pic. 

PImage photo; 
PImage imageFlash;

String api_key = "fbdd84ed5fab78b1384f943cf5fd3e69";
String api_secret = "7IpVkigS2UeSnDYWGhD3XDTAKdMyeffb";

String jonImg = "/Users/jrogers/Documents/Processing/faceplusplus_with_cam/data/jon.jpg";
String photoImg = "/Users/jrogers/Documents/Processing/faceplusplus_with_cam/data/camPhoto.jpg";


int matVal=0; // holds current value of Arduino pin MAT_PIN
int matOld=0; // previous value of Arduino pin MAT_PIN
int state = 0; // used to control interaction state machine
int timeNow=0;  // used for state machine
int timeStart; //  initialise state machine
int flash = 0;  // is the camera "flash' on (1) off (0) - should be a bool I know.. 
int picCount = 0; // counts number of times a pic is taken. used to determine if no face is there
int photoAge;  

// SETUP ---------------------------- 

public void setup() 
{
  size(640, 360);  // Apple FT camera [3] 640x360 at 30fps
  // size(1280,720);  // use for larger cam... 

  // set up the camera 

  photo = loadImage(jonImg); 
  //set up camera

  //CAMERA SETUP
  String[] cameras = Capture.list();
  if (cameras == null) {
    println("Failed to retrieve the list of available cameras, will try the default...");
    // cam = new Capture(this, 640, 480);
  } 
  if (cameras.length == 0) {
    println("There are no cameras available for capture.");
    exit();
  } else {
    println("Available cameras:");
    for (int i = 0; i < cameras.length; i++) {
      println(cameras[i]);
    }
    println(cameras[3]);
    cam = new Capture(this, cameras[3]); // 15 when usb cam on (or check other) - testing with FT cam - fps 1? cam  
    //cam = new Capture(this, 1280, 960);
    cam.start();
  }

  // POST set up --------------------------------------------------------------------
  post = new PostRequest("https://apius.faceplusplus.com/v2/detection/detect");

  post.addData("api_key", api_key);
  post.addData("api_secret", api_secret);

  // I needed full path to the image file since relative wasn't working for PostRequest library.
  // Obviously, with the camera you will need to save the PImage as a File before doing this.
  // Also note, you can call post.addFile with the second argument being a Java File object, if that's easier.
  // post.addFile("img", "/Users/mikehenrty/Documents/Processing/simple_json_POST_forFace__base64/data/jon.jpg");
  post.addFile("img", jonImg);


  // do a test on on jon.jpg - comes up with 39. 
  post.send();
  println(post.getContent());
  JSONObject response = parseJSONObject(post.getContent());
  JSONArray face = response.getJSONArray("face");
  JSONObject attribute = face.getJSONObject(0);
  JSONObject at2 = attribute.getJSONObject("attribute");
  JSONObject age = at2.getJSONObject("age");
  println ("Welcome Jon your age is..." + age.getInt("value"));
  photoAge = age.getInt("value"); 
  println ("photo age = " + photoAge); 

  // Arduino set up --------------------------------------------------------------------
  // make sure you have STANDARD FIRMATA installed on an Arduino Uno. 

  println(Arduino.list());
  arduino = new Arduino(this, Arduino.list()[5], 57600); // check if it's on 5
  arduino.pinMode(FLASH_PIN, Arduino.OUTPUT);
  arduino.pinMode(MAT_PIN, Arduino.INPUT);

  //minim (audio player) set up
  minim = new Minim(this);
  //song = minim.loadFile("data/audio/test.mp3", 512);




  println ("starting draw");
}

// DRAW --------------------------------------------------------------------


void draw()
{
  
  int playSong=0; 

  /*
   0 = checking for mat
   1= mat stepped on take picture and flash
   2 = send picture to rekognition first and start playing track
   3 = start printing - lock out any new mat activity (for 27.5seconds  27500ms 
   and at end of printing - unlock mat and return state to 0
   */
  //println(state); 
  // onnly do if the camera is availalbe - esle baile
  if (cam.available()) {
    cam.read();
    image(cam, 0, 0);
    if (flash==1) {
      arduino.digitalWrite(FLASH_PIN, arduino.HIGH); 
      //cam.read(); // maybe redundant? 
      //image(cam, 0, 0);
    } else
    {
      arduino.digitalWrite(FLASH_PIN, arduino.LOW);
    }

    switch(state) {
    case 0:
      // read the mat and look for state change
      //  arduino.digitalWrite(FLASH_PIN, arduino.LOW); 
      matOld = matVal; 
      matVal = arduino.digitalRead(MAT_PIN);
      if ((matVal==1) && (matOld==0)) { 
        timeStart=millis();
        state = 1; // the mat has been stepped on
      }
      break;

      // wait for a bit until we start the flash...

    case 1:
      timeNow = millis(); 
      if (timeNow-timeStart > MAT_DELAY)
      {
        timeStart=millis();
        state=2;
      }
      break;
    case 2:
      // flash and take picture      
      timeNow=millis(); 
      flash = 1; 

      imageFlash = get(0, 0, width, height);
      if (timeNow-timeStart>CAM_FLASH) {
        flash = 0; 
        state = 3;
      } 
      break;

    case 3:

      flash = 0; 
      // do face recognition  
      int songY= facePlusPlus_get(imageFlash);
      println("song year", songY);

      // if there is no face rekognised - then try again. Q - how many times? 5?
      if (songY==0)
      {
        // no face recognised.
        // take another picuture - do this up to 5 times
        picCount = picCount+1;
        if (picCount <MAX_CAM_TRY)
          state =  2;
        else 
        {
          state = 0;
          picCount = 0;
        }
      } else
      {
        // we have a year... carry on
        println("playing song from " + songY); 
        playTrack(songY);
        state = 4;
      }

      break;

    case 4:
      // print image on a TapWriter
      // NOT IN THIS VERSION - BUT HOLD FOR FUTURE VERSION 
      println("all done"); 
      // might need to put FTP time allowqance here?
      timeStart = millis(); // should be ok to reset the timer now
      state = 5;      
      break;  

    case 5: 
      timeNow = millis(); 
      if (timeNow-timeStart>MIN_PLAY_TIME)
        state=0;       
      break;
    }
  }
  
  // displayed perceived age...
  fill(200, 30, 30);
  textSize(60);
  text(photoAge, 330, 100);
}


int facePlusPlus_get(PImage im)
{
  int songYear;
  // in mirror code this will be the mat being stepped on.. . 

  // take a picture 

  image(im, 0, 0); 
  PImage screengrab = createImage(width, height, ALPHA);
  save(photoImg); 

  // post it 
  post = new PostRequest("https://apius.faceplusplus.com/v2/detection/detect");

  post.addData("api_key", api_key);
  post.addData("api_secret", api_secret);

  // I needed full path to the image file since relative wasn't working for PostRequest library.
  // Obviously, with the camera you will need to save the PImage as a File before doing this.
  // Also note, you can call post.addFile with the second argument being a Java File object, if that's easier.
  // post.addFile("img", "/Users/mikehenrty/Documents/Processing/simple_json_POST_forFace__base64/data/jon.jpg");
  post.addFile("img", photoImg);
  post.send();
  println(post.getContent());

  JSONObject response = parseJSONObject(post.getContent());
  try {
    JSONArray face = response.getJSONArray("face");
    JSONObject attribute = face.getJSONObject(0);
    JSONObject at2 = attribute.getJSONObject("attribute");
    JSONObject age = at2.getJSONObject("age");
    println ("Welcome Jon your age is..." + age.getInt("value"));

    photoAge = age.getInt("value");

    // tidying up the lack of songs from years - grouping...

    songYear = 2029-photoAge; // jNote does this need to be 2030 now it's 2016.. keep for V&A
    if (songYear <= 1939) {
      songYear = 1930;
    }
    if (songYear >= 1940 && songYear <= 1949) {
      songYear = 1940;
    }
    if (songYear >= 1950 && songYear <= 1955) {
      songYear = 1950;
    }
    if (songYear >= 1956 && songYear <= 1959) {
      songYear = 1956;
    }
    if (songYear >= 1960 && songYear <= 1962) {
      songYear = 1960;
    }
    if (songYear >= 1963 && songYear <= 1665) {
      songYear = 1963;
    }
    if (songYear >= 1966 && songYear <= 1969) {
      songYear = 1966;
    }

    if (songYear > 2014 ) {
      songYear = 2014;
    }
  } 
  catch (Exception e)
  { 
    e.printStackTrace();
    println("sorry, couldnt' find your age");
    songYear = 0;
  }

  // set age. 



  return songYear;
}

void playTrack(int trackYear)

{
  //MP3 STUFF -------------------------------------------

  //Get random sub name for song from year

  String [] letter = {
    "a", "b", "c", "d", "e"
  };
  int index = int(random(letter.length));
  // println(letter[index]);
  // println("data/audio/"+songYear+letter[index]+".mp3");
 
  String f; 
  f = "data/audio/"+trackYear+letter[index]+".mp3"; 
  println("playing song", f); 
  song = minim.loadFile("data/audio/"+trackYear+letter[index]+".mp3", 512);
  if (song.isPlaying()) {
    song.pause();
    delay (50);
    minim.stop();
  } else
  {
    song.pause();
    delay (50);
    minim.stop();
  }

  song = minim.loadFile("data/audio/"+trackYear+letter[index]+".mp3", 512);
  if ( song == null ) println("Didn't get song!");
  song.play();
  println("playing track "+trackYear+letter[index]+".mp3 \r\r");
}



// ------------------------ KEY PRESSED ----------------

// a test of the API - no sound played - just guesssed year. Press any key.. 

void keyReleased() {
  // using this as a test for when there is no Arduino (to test Face++ API) 

  // take a picture 

  image(cam, 0, 0); 
  PImage screengrab = createImage(width, height, ALPHA);
  save(photoImg); 

  // post it 
  post = new PostRequest("https://apius.faceplusplus.com/v2/detection/detect");

  post.addData("api_key", api_key);
  post.addData("api_secret", api_secret);

  // I needed full path to the image file since relative wasn't working for PostRequest library.
  // Obviously, with the camera you will need to save the PImage as a File before doing this.
  // Also note, you can call post.addFile with the second argument being a Java File object, if that's easier.
  // post.addFile("img", "/Users/mikehenrty/Documents/Processing/simple_json_POST_forFace__base64/data/jon.jpg");


  post.addFile("img", photoImg);

  post.send();


  println(post.getContent());


  JSONObject response = parseJSONObject(post.getContent());
  try {
    JSONArray face = response.getJSONArray("face");
    JSONObject attribute = face.getJSONObject(0);
    JSONObject at2 = attribute.getJSONObject("attribute");
    JSONObject age = at2.getJSONObject("age");
    println ("Welcome Jon your age is..." + age.getInt("value"));

    photoAge = age.getInt("value");
  } 
  catch (Exception e)

  { 
    e.printStackTrace();
    println("sorry, couldnt' find your age");
  }

  // set age. 

  // would be nicer to have in a set of functions - but the void keyReleased forces this rough hack... will do for now..
}