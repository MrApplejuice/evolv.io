Board evoBoard;
final int SEED = parseInt(random(1000000));
final float NOISE_STEP_SIZE = 0.1;
final int BOARD_WIDTH = 100;
final int BOARD_HEIGHT = 100;

final float SCALE_TO_FIX_BUG = 100;

final double TIME_STEP = 0.001;
final float MIN_TEMPERATURE = -0.5;
final float MAX_TEMPERATURE = 1.0;

final int ROCKS_TO_ADD = 500;
final int CREATURE_MINIMUM = 300;

float scaleFactor;
int windowWidth;
int windowHeight;
float cameraX = BOARD_WIDTH * 0.5;
float cameraY = BOARD_HEIGHT * 0.5;
float cameraR = 0;
float zoom = 1;
PFont font;
int dragging = 0; // 0 = no drag, 1 = drag screen, 2 and 3 are dragging temp extremes.
float prevMouseX;
float prevMouseY;
boolean draggedFar = false;
final String INITIAL_FILE_NAME = "PIC";

void settings() {
  // Get users window size
  windowWidth = 1600;
  windowHeight = 900;

  // Set scaling to be custom to current users screen size
  scaleFactor = ((float)windowHeight)/BOARD_HEIGHT/SCALE_TO_FIX_BUG;

  // Allow window to be docked and resized the UI still needs to be changed to make UI look good after resize
  size(windowWidth, windowHeight);
}

/**
  The Hail-Mary attempt to let the evoBoard run in parallel to - at least -
  the draw loop.
  
  This class has two modes:
  
   - free run mode: 
       freeRunCounter is negative, simulation is running as fast as possible
   - counter mode:
       more or less the classical mode but this time implemented with multi
       threading. Runs until the counter reaches zero and then pauses until
       sync() is called.
       
  To synchronize with the loop, and then call sync() on it to wait until a
  simulation sycle ends.
 */
class SimThread extends Thread {
  private boolean threadIsLockedUp = false;
  
  private int freeRunMode = 1;
  private int freeRunCounter = 0;
  
  public synchronized void setFreerunMode() {
    freeRunMode = -1;
  }
  
  public synchronized void setCounterMode(int counter) {
    freeRunMode = counter;
  }
  
  /**
     Waits for a simulation cycle to end and then returns
     control to the main program.
   */
  public synchronized void sync() {
    try {
      if (freeRunCounter >= 0) {
        while ((freeRunCounter > 0) && (!threadIsLockedUp)) {
          wait();
        }
      }
    }
    catch (InterruptedException e) {
      Thread.currentThread().interrupt();
    }
  }
  
  public synchronized void startNextCycle() {
    sync();
    if (threadIsLockedUp) {
      notifyAll();
    }
  }
  
  public void run() {
    while (!Thread.interrupted()) {
      if (freeRunCounter > 0) {
        evoBoard.iterate(TIME_STEP);
        freeRunCounter -= 1;
      }
      
      synchronized(this) {
        this.notifyAll();
        
        if (freeRunCounter == 0) {
          threadIsLockedUp = true;
          evoBoard.boardSimulationCycleSW.lap();
          try {
            this.wait();
          }
          catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return;
          }
          evoBoard.boardSimulationCycleSW.start();
          
          freeRunCounter = freeRunMode;
          threadIsLockedUp = false;
        }
      }
    }
  }
};

SimThread simThread = new SimThread();


void exit() {
  if (simThread.isAlive()) {
    simThread.interrupt();
    try {
      simThread.join();
    }
    catch (InterruptedException e) {
      Thread.currentThread().interrupt();
    }
  }
  
  evoBoard.stop();
  
  super.exit();
}

void setup() {
  surface.setResizable(true);
  colorMode(HSB, 1.0);
  font = loadFont("Jygquip1-48.vlw");
  evoBoard = new Board(BOARD_WIDTH, BOARD_HEIGHT, NOISE_STEP_SIZE, MIN_TEMPERATURE, MAX_TEMPERATURE, 
    ROCKS_TO_ADD, CREATURE_MINIMUM, SEED, INITIAL_FILE_NAME, TIME_STEP);
  resetZoom();
  
  simThread.setCounterMode(evoBoard.playSpeed);
  simThread.start();
}

void draw() {
  if (dist(prevMouseX, prevMouseY, mouseX, mouseY) > 5) {
    draggedFar = true;
  }

  synchronized (simThread) {
    simThread.sync();
    
    synchronized (evoBoard) {
      if (dragging == 1) {
        cameraX -= toWorldXCoordinate(mouseX, mouseY) - toWorldXCoordinate(prevMouseX, prevMouseY);
        cameraY -= toWorldYCoordinate(mouseX, mouseY) - toWorldYCoordinate(prevMouseX, prevMouseY);
      } else if (dragging == 2) { // UGLY UGLY CODE.  Do not look at this
        if (evoBoard.setMinTemperature(1.0 - (mouseY - 30) / 660.0)) {
          dragging = 3;
        }
      } else if (dragging == 3) {
        if (evoBoard.setMaxTemperature(1.0 - (mouseY - 30) / 660.0)) {
          dragging = 2;
        }
      }
      if (evoBoard.userControl && evoBoard.selectedCreature != null) {
        final Vector2D cameraPos = evoBoard.selectedCreature.getPosition();
        cameraX = (float) cameraPos.getX();
        cameraY = (float) cameraPos.getY();
        cameraR = -PI / 2.0 - (float) evoBoard.selectedCreature.getRotation();
      } else {
        cameraR = 0;
      }
      pushMatrix();
      scale(scaleFactor);
      evoBoard.drawBlankBoard(SCALE_TO_FIX_BUG);
      translate(BOARD_WIDTH * 0.5 * SCALE_TO_FIX_BUG, BOARD_HEIGHT * 0.5 * SCALE_TO_FIX_BUG);
      scale(zoom);
      if (evoBoard.userControl && evoBoard.selectedCreature != null) {
        rotate(cameraR);
      }
      translate(-cameraX * SCALE_TO_FIX_BUG, -cameraY * SCALE_TO_FIX_BUG);
      evoBoard.drawBoard(SCALE_TO_FIX_BUG, zoom, (int)toWorldXCoordinate(mouseX, mouseY), (int)toWorldYCoordinate(mouseX, mouseY));
      popMatrix();
      evoBoard.drawUI(SCALE_TO_FIX_BUG, zoom, TIME_STEP, windowHeight, 0, windowWidth, windowHeight, font);
    
      evoBoard.fileSave();
      prevMouseX = mouseX;
      prevMouseY = mouseY;
    }
    
    simThread.startNextCycle();
  }
}

void mouseWheel(MouseEvent event) {
  float delta = event.getCount();
  if (delta >= 0.5) {
    setZoom(zoom * 0.90909, mouseX, mouseY);
  } else if (delta <= -0.5) {
    setZoom(zoom*1.1, mouseX, mouseY);
  }
}

void mousePressed() {
  synchronized (evoBoard) {
    if (mouseX < windowHeight) {
      dragging = 1;
    } else {
      if (abs(mouseX - (windowHeight + 65)) <= 60 && abs(mouseY - 147) <= 60 && evoBoard.selectedCreature != null) {
        final Vector2D cameraPos = evoBoard.selectedCreature.getPosition();
        cameraX = (float) cameraPos.getX();
        cameraY = (float) cameraPos.getY();
        zoom = 16;
      } else if (mouseY >= 95 && mouseY < 135 && evoBoard.selectedCreature == null) {
        if (mouseX >= windowHeight + 10 && mouseX < windowHeight + 230) {
          resetZoom();
        } else if (mouseX >= windowHeight + 240 && mouseX < windowHeight + 460) {
          if (mouseButton == LEFT) {
            evoBoard.incrementSort();
          }
          else if (mouseButton == RIGHT){
            evoBoard.decrementSort();
          }
        }
      } else if (mouseY >= 570) {
        float x = (mouseX - (windowHeight + 10));
        float y = (mouseY - 570);
        boolean clickedOnLeft = (x % 230 < 110);
        if (x >= 0 && x < 460 && y >= 0 && y < 200 && x % 230 < 220 && y % 50 < 40) { // 460 = 2 * 230 and 200 = 4 * 50
          int mX = (int)(x / 230);
          int mY = (int)(y / 50);
          int buttonNum = mX + mY * 2;
  
  
          switch(buttonNum) {
  
            case(0):
            evoBoard.userControl = !evoBoard.userControl;
            break;
  
            case(1):
            if (clickedOnLeft) {
              evoBoard.creatureMinimum -= evoBoard.creatureMinimumIncrement;
            } else {
              evoBoard.creatureMinimum += evoBoard.creatureMinimumIncrement;
            }
            break;
  
            case(2):
            evoBoard.prepareForFileSave(0);
            break;
  
            case(3):
            if (clickedOnLeft) {
              evoBoard.imageSaveInterval *= 0.5;
            } else {
              evoBoard.imageSaveInterval *= 2.0;
            }
            if (evoBoard.imageSaveInterval >= 0.7) {
              evoBoard.imageSaveInterval = Math.round(evoBoard.imageSaveInterval);
            }
            break;
  
            case(4):
            evoBoard.prepareForFileSave(2);
            break;
  
            case(5):
            if (clickedOnLeft) {
              evoBoard.textSaveInterval *= 0.5;
            } else {
              evoBoard.textSaveInterval *= 2.0;
            }
            if (evoBoard.textSaveInterval >= 0.7) {
              evoBoard.textSaveInterval = Math.round(evoBoard.textSaveInterval);
            }
            break;
  
            case(6):
            if (clickedOnLeft) {
              if (evoBoard.playSpeed >= 2) {
                evoBoard.playSpeed /= 2;
              } else {
                evoBoard.playSpeed = 0;
              }
            } else {
              if (evoBoard.playSpeed == 0) {
                evoBoard.playSpeed = 1;
              } else {
                evoBoard.playSpeed *= 2;
              }
            }
            simThread.setCounterMode(evoBoard.playSpeed);
            break;
  
            case(7):
              evoBoard.showPerformanceWindow();
            break;
          }
        }
      } else if (mouseX >= height + 10 && mouseX < width - 50 && evoBoard.selectedCreature == null) {
        int listIndex = (mouseY-150)/70;
        if (listIndex >= 0 && listIndex < evoBoard.LIST_SLOTS) {
          evoBoard.selectedCreature = evoBoard.list[listIndex];
          final Vector2D cameraPos = evoBoard.selectedCreature.getPosition();
          cameraX = (float) cameraPos.getX();
          cameraY = (float) cameraPos.getY();
          zoom = 16;
        }
      }
      if (mouseX >= width - 50) {
        float toClickTemp = (mouseY - 30) / 660.0;
        float lowTemp = 1.0 - evoBoard.getLowTempProportion();
        float highTemp = 1.0 - evoBoard.getHighTempProportion();
        if (abs(toClickTemp - lowTemp) < abs(toClickTemp - highTemp)) {
          dragging = 2;
        } else {
          dragging = 3;
        }
      }
    }
    draggedFar = false;
  }
}

void mouseReleased() {
  if (!draggedFar) {
    synchronized (evoBoard) {
      if (mouseX < windowHeight) { // DO NOT LOOK AT THIS CODE EITHER it is bad
        dragging = 1;
        final Vector2D worldClickCoordinate = new Vector2D().set(toWorldXCoordinate(mouseX, mouseY), toWorldYCoordinate(mouseX, mouseY));
        evoBoard.unselect();
        cameraR = 0;
        System.out.println(worldClickCoordinate);
        for (final SoftBody body : evoBoard.getSoftBodiesAtPosition(worldClickCoordinate)) { 
          if (Creature.class.isInstance(body)) {
            final Creature creature = Creature.class.cast(body);
            System.out.println(creature.getPosition().distance(worldClickCoordinate));
            if (creature.getPosition().distance(worldClickCoordinate) <= creature.getRadius()) {
              evoBoard.selectedCreature = creature;
              zoom = 16;
            }
          }
        }
      }
    }
  }
  dragging = 0;
}

void resetZoom() {
  cameraX = BOARD_WIDTH * 0.5;
  cameraY = BOARD_HEIGHT * 0.5;
  zoom = 1;
}

void setZoom(float target, float x, float y) {
  float grossX = grossify(x, BOARD_WIDTH);
  cameraX -= (grossX / target - grossX / zoom);
  float grossY = grossify(y, BOARD_HEIGHT);
  cameraY -= (grossY / target - grossY / zoom);
  zoom = target;
}

float grossify(float input, float total) { // Very weird function
  return (input / scaleFactor - total * 0.5 * SCALE_TO_FIX_BUG) / SCALE_TO_FIX_BUG;
}

float toWorldXCoordinate(float x, float y) {
  float w = windowHeight / 2;
  float angle = atan2(y - w, x - w);
  float dist = dist(w, w, x, y);
  return cameraX + grossify(cos(angle - cameraR) * dist + w, BOARD_WIDTH) / zoom;
}

float toWorldYCoordinate(float x, float y) {
  float w = windowHeight / 2;
  float angle = atan2(y - w, x - w);
  float dist = dist(w, w, x, y);
  return cameraY + grossify(sin(angle - cameraR) * dist + w, BOARD_HEIGHT) / zoom;
}