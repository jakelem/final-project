import {glMatrix, vec2, vec3} from 'gl-matrix';
const Stats = require('stats-js');
const DAT = require('dat.gui');

import Square from './geometry/Square';
import OpenGLRenderer from './rendering/gl/OpenGLRenderer';
import Camera from './Camera';
import {setGL} from './globals';
import ShaderProgram, {Shader} from './rendering/gl/ShaderProgram';
var randGen = require('random-seed');

// Define an object with application parameters and button callbacks
// This will be referred to by dat.GUI's functions that add GUI elements.
interface ParamList {
  [index: string]: any
}


const controls : ParamList = {
  'Weight': 1.1,
  'Posture': -0.54,

  'Neck Length': 1.77,
  'Neck Width': 0.73,

  'Body Length': 1.3,

  'Skull Size': 0.5,
  'Skull Length': 0.25,

  'Head Shape' : 0.0,

  // Curviness
  'Neck Shape' : 0.0,

  // angle about z axis
  'Tail Angle' : -1.0,
  'Tail Spread' : 1.0,
  'Tail Length' : 3.0,

  // Wing
    // TODO: Create primary and secondary wings in shader

  'Leg Height' : 2.5,

  'Wing Spread' : 0.7,
  'Wing Length' : 1.0,

  'Beak Shape' : 0.0,
  'Beak Height' : 0.16,
  'Beak Length' : 1.0,

  'Upper Tail Covert Length' : 0.0,
  'Color 1': [102,51,25],
  'Color 2': [15,15,18],
  'Color 3': [17,15,15],
  'Color 4': [255,245,233],
  'Color 5': [167,88,10],

  'Texture Seed' : 0.0,
};


const controlIntervals : ParamList = {
  'Weight': [0.9, 1.4],
  'Posture': [-3.1415 * 0.25, 3.1415 * 0.06],
  'Neck Length': [0.5, 3.0], 
  'Neck Width': [0.3, 0.8], 
  'Body Length': [1.0, 1.6],
  'Skull Size': [0.5, 0.8], 
  'Skull Length': [0.05, 0.5], 
  'Beak Height': [0.05, 0.25], 
  'Beak Length': [0.1, 1.0], 
  'Tail Angle': [-3.1415 * 0.25, 3.1415 * 0.25], 
  'Tail Spread': [0.01, 1.3], 
  'Tail Length': [0.5, 3.4], 
  'Leg Height': [1.0, 3.0], 
  'Wing Spread': [0.5, 0.8], 
  'Wing Length': [0.5, 1.4], 

}

let square: Square;
let time: number = 0;
let birdParams: Array<number>;
let colorParams: Array<number>;
function loadScene() {
  square = new Square(vec3.fromValues(0, 0, 0));
  square.create();
  // time = 0;
}

function mix(x : number, y: number, a: number){
  return x * (1 - a) + y * a;
}

function normalizeColArr(colArr : number[]) {
  return [colArr[0] / 255.0, colArr[1] / 255.0, colArr[2] / 255.0];
}

function updateGUI(g : any) {
  for (let i in g.__controllers) {
    g.__controllers[i].updateDisplay();
  }

  for (let i in g.__folders) {
    updateGUI(g.__folders[i]);
  }
}


function main() {
  let rand = randGen.create();

  birdParams = new Array<number>();
  colorParams = new Array<number>();

  for(let i = 0; i < 20; ++i) {
    birdParams.push(0.0);
  }

  // Initial display for framerate
  const stats = Stats();
   stats.setMode(0);
   stats.domElement.style.position = 'absolute';
   stats.domElement.style.left = '0px';
   stats.domElement.style.top = '0px';
  document.body.appendChild(stats.domElement);

  const gui = new DAT.GUI();

    for (var key in controlIntervals) {
      gui.add(controls, key, 
        controlIntervals[key][0], 
        controlIntervals[key][1]).onChange(function() {
          setAllBirdParams()
        });    
      }
    
    
  gui.add(controls, 'Texture Seed').onChange( function() {
    setAllBirdParams()
  });

  gui.addColor(controls, 'Color 1').onChange( function() {
    setAllBirdParams()
  });

  gui.addColor(controls, 'Color 2').onChange( function() {
    setAllBirdParams()
  });

  gui.addColor(controls, 'Color 3').onChange( function() {
    setAllBirdParams()
  });

  gui.addColor(controls, 'Color 4').onChange( function() {
    setAllBirdParams()
  });

  gui.addColor(controls, 'Color 5').onChange( function() {
    setAllBirdParams()
  });

function randomColor(scale = 1) {
  return [scale * rand.floatBetween(0, 255), 
          scale * rand.floatBetween(0, 255), 
          scale * rand.floatBetween(0, 255)
          ];
}


function randomize() {
  for (var key in controlIntervals) {
    controls[key] = rand.floatBetween(controlIntervals[key][0], controlIntervals[key][1]);
  }

  controls['Color 1'] = randomColor(0.8);
  controls['Color 2'] = randomColor(0.5);
  controls['Color 3'] = randomColor(0.5);
  controls['Color 4'] = randomColor(0.8);
  controls['Color 5'] = randomColor(0.8);
  controls['Texture Seed'] = rand.floatBetween(0, 200);

  updateGUI(gui)
  setAllBirdParams()

}

// Initialize here to deal with scope issues
  var randomizeButton = {'Randomize' : randomize}

  gui.add(randomizeButton, 'Randomize');


  window.addEventListener('keypress', function (e) {
    // console.log(e.key);
    switch(e.key) {
      case 'r':
        controls["Texture Seed"]+=1.0;
        updateGUI(gui)
        setAllBirdParams()
        break
      case 'e':
        controls["Texture Seed"]-=1.0;
        updateGUI(gui)
        setAllBirdParams()
        break
    }
  }, false);

  window.addEventListener('keyup', function (e) {
    switch(e.key) {
      // Use this if you wish
    }
  }, false);
  

  function setAllBirdParams() {
    /*
    let lowerBodyWidth = controls['Weight'] * 0.9 + 0.1;
    let breastWidth = controls['Weight'] * 1.2;
    let upperNeckWidth = controls['Neck Width'] * controls['Weight'] * 0.9;
    let lowerNeckWidth = mix(upperNeckWidth, breastWidth, 0.4);
    let headWidth = mix(upperNeckWidth, 0.7, 0.8);*/
    //let rand = randGen.create();
    //this.rand.seed(this.seed);

    birdParams[0] = controls['Weight'];  
    birdParams[1] = controls['Neck Length'];  
    birdParams[2] = controls['Neck Width'];  
    birdParams[3] = controls['Skull Size'];  
    birdParams[4] = controls['Tail Angle'];  
    birdParams[5] = controls['Tail Spread'];  
    birdParams[6] = controls['Tail Length'];  
    birdParams[7] = controls['Leg Height'];  
    birdParams[8] = controls['Skull Length'];  
    birdParams[9] = controls['Beak Height'];  
    birdParams[10] = controls['Beak Length'];  
    birdParams[11] = controls['Texture Seed'] * 0.0001;  
    birdParams[13] = controls['Wing Spread'];  
    birdParams[14] = controls['Wing Length'];  
    birdParams[15] = controls['Posture'];  
    birdParams[16] = controls['Body Length'];  

    flat.setBirdParams(birdParams);

    colorParams = new Array<number>();
    colorParams = colorParams.concat(normalizeColArr(controls['Color 1']),
    normalizeColArr(controls['Color 2']),
    normalizeColArr(controls['Color 3']),
    normalizeColArr(controls['Color 4']),
    normalizeColArr(controls['Color 5']));  

    console.log(colorParams)
    flat.setBirdColors(colorParams);

  }

  // get canvas and webgl context
  const canvas = <HTMLCanvasElement> document.getElementById('canvas');
  const gl = <WebGL2RenderingContext> canvas.getContext('webgl2');
  if (!gl) {
    alert('WebGL 2 not supported!');
  }
  // `setGL` is a function imported above which sets the value of `gl` in the `globals.ts` module.
  // Later, we can import `gl` from `globals.ts` to access it
  setGL(gl);

  // Initial call to load scene
  loadScene();

  const camera = new Camera(vec3.fromValues(-4, 0, -12), vec3.fromValues(0, 0, 0));

  const renderer = new OpenGLRenderer(canvas);
  renderer.setClearColor(0.0, 1.0, 1.0, 1);
  gl.enable(gl.DEPTH_TEST);

  const flat = new ShaderProgram([
    new Shader(gl.VERTEX_SHADER, require('./shaders/flat-vert.glsl')),
    new Shader(gl.FRAGMENT_SHADER, require('./shaders/flat-frag.glsl')),
  ]);

  const post = new ShaderProgram([
    new Shader(gl.VERTEX_SHADER, require('./shaders/passthrough-vert.glsl')),
    new Shader(gl.FRAGMENT_SHADER, require('./shaders/postprocess-frag.glsl')),
  ]);


  function processKeyPresses() {
    // Use this if you wish
  }

  // This function will be called every frame
  function tick() {

    camera.update();
    stats.begin();
    gl.viewport(0, 0, window.innerWidth, window.innerHeight);
    renderer.clear();
    processKeyPresses();

    
    renderer.render(camera, flat, [
      square,
    ], time);

    post.setBaseColorTexture(flat.targetTexture1)
    post.setDepthTexture(flat.targetTexture2)

    renderer.render(camera, post, [
      square,
    ], time);
    
    time++;
    stats.end();

    // Tell the browser to call `tick` again whenever it renders a new frame
    requestAnimationFrame(tick);
  }

  window.addEventListener('resize', function() {
    renderer.setSize(window.innerWidth, window.innerHeight);
    camera.setAspectRatio(window.innerWidth / window.innerHeight);
    camera.updateProjectionMatrix();
    flat.setDimensions(window.innerWidth, window.innerHeight);
    flat.setSize(window.innerWidth, window.innerHeight);
    post.setSize(window.innerWidth, window.innerHeight);
    post.setDimensions(window.innerWidth, window.innerHeight);

    flat.frameBufferResize();

  }, false);

  

  renderer.setSize(window.innerWidth, window.innerHeight);
  camera.setAspectRatio(window.innerWidth / window.innerHeight);
  camera.updateProjectionMatrix();
  flat.setDimensions(window.innerWidth, window.innerHeight);
  flat.setSize(window.innerWidth, window.innerHeight);
  post.setSize(window.innerWidth, window.innerHeight);
  post.setDimensions(window.innerWidth, window.innerHeight);

  flat.createFrameBuffer1();

  setAllBirdParams()
  // Start the render loop
  tick();
}

main();
