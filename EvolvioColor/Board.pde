import java.io.*;
import java.util.List;
import java.util.Iterator;

public static final List<SoftBody> EMPTY_SOFT_BODY_LIST = new ArrayList<SoftBody>();

/**
  Handler interaface for synchrnozied handling of tile interactions.
 */
public interface SynchronizedTileInteraction {
  public void handleTile(Tile tile);
}

/**
  More abstraction layers to /some/ interaction between Creatues and the board.
  
  This must be in a super-controlled manner however to make multithreading efficient 
  and also prevent deadlocks.
 */
public interface AbstractBoardInterface {
  // Adds a new creature to the Board (reproduction)
  public void addCreature(Creature creature);
  
  public int getBoardWidth();
  public int getBoardHeight();
  
  // Returns the board's background color
  public color getBackgroundColor();
  
  /**
    Returns a tile's color given its x and y coordinate.
    If x and y are outside the board size, the result
    will be the background color
   */
  public color getTileColor(Vector2D pos);
  
  /**
     Returns the a list of soft bodies at the given location.
   */
  public List<SoftBody> getSoftBodiesAtPosition(Vector2D pos);
  
  /**
    Starts a synchronized transation with a tile at the given location.
    
    Returns fals if the location was out of bounds!
   */
  public boolean interactWithTileAtLocation(Vector2D location, SynchronizedTileInteraction handler);
};

interface DrawConfiguration {
  public float getStrokeWeight();
};

/**
  This class exposes variables to EVERYTHING. Efficient parallelization
  of execution is not possible while other classes are so tightly coupled 
  with this class. I will spend some work on making more of this class private
  so that especially Creatures can be somewhat more decoupled from the board
  they live on.
  
  In the future the UI elements should als obe stripped from this class...
 */
class Board implements AbstractBoardInterface, DrawConfiguration {
  /**
    Class distributing the simulation of creatures among different
    worker threads.
   */
  private class WorkDistributor {
    private List<Creature> creatureList;
    private int globalIndex = 0;
    private int dispatchIndex = 0;
    private boolean cycleRunning = false;
    
    private int cycleStartSize = 0;
    
    public WorkDistributor(List<Creature> creatureList) {
      this.creatureList = creatureList;
    }
    
    /**
      Blocks until a new workitem can be popped.
     */
    public synchronized Creature popCreature() throws InterruptedException {
      if (cycleRunning) {
        //System.out.println("returning from: " + globalIndex + "  " + cycleStartSize);
        globalIndex++;
      }
      notifyAll();
      while ((!cycleRunning) || (dispatchIndex >= cycleStartSize)) {
        wait();
      }
      //System.out.println("serving: " + dispatchIndex + "  " + cycleStartSize);
      return creatureList.get(dispatchIndex++);
    }
    
    /**
      Restarts a new processing cycle. Blocks until the processing
      cycle has finished.
     */
    public synchronized void cycle() {
      try {
        while (cycleRunning) {
          wait();
        }
        
        globalIndex = 0;
        dispatchIndex = 0;
        cycleStartSize = creatureList.size();
        cycleRunning = true;
        
        notifyAll();
        while (globalIndex < cycleStartSize) {
          wait();
        }
        
        cycleRunning = false;
      }
      catch (InterruptedException e) {
        Thread.currentThread().interrupt();
      }
    }
  };
  
  private class CreatureWorkerThread extends Thread {
    private WorkDistributor workDistributor;
    
    public CreatureWorkerThread(WorkDistributor workDistributor) {
      this.workDistributor = workDistributor;
    }
    
    public void run() { 
      while (!Thread.interrupted()) {
        try {
          final Creature me = workDistributor.popCreature();
          me.collide(timeStep);
          me.see(timeStep);
          me.metabolize(timeStep, year);
          me.useBrain(timeStep, !userControl, Board.this.year);
        }
        catch (InterruptedException e) {
          Thread.currentThread().interrupt();
        }
      }
    }
  };

  
  public static final float MIN_CREATURE_ENERGY = 1.2;
  public static final float MAX_CREATURE_ENERGY = 2.0;
  public static final float MINIMUM_SURVIVABLE_SIZE = 0.06;
  public static final float CREATURE_STROKE_WEIGHT = 0.6;

  public static final int WORKER_THREAD_COUNT = 4;
  
  // Board
  private int boardWidth;
  private int boardHeight;
  
  private Tile[][] tiles;

  // Creature
  int creatureMinimum;
  
  private ArrayList<SoftBody>[][] softBodiesInPositions;

  private WorkDistributor workDistributor;
  private List<Thread> workerThreads = new ArrayList<Thread>(); 
  
  private ArrayList<Creature> newCreatures = new ArrayList<Creature>();
  private ArrayList<Creature> creatures = new ArrayList<Creature>(0);

  private int uniqueIdCounter = 0;
  
  
  Creature selectedCreature = null;
  private int creatureRankMetric = 0;
  final int LIST_SLOTS = 6;
  Creature[] list = new Creature[LIST_SLOTS];
  final int creatureMinimumIncrement = 5;
  double MANUAL_BIRTH_SIZE = 1.2;
  boolean wasPressingB = false;

  // Time or History
  double year = 0;
  final float OBJECT_TIMESTEPS_PER_YEAR = 100;
  double timeStep;
  int POPULATION_HISTORY_LENGTH = 200;
  int[] populationHistory;
  double recordPopulationEvery = 0.02;
  int playSpeed = 1;

  // Temperature
  float MIN_TEMPERATURE;
  float MAX_TEMPERATURE;
  final float THERMOMETER_MIN = -2;
  final float THERMOMETER_MAX = 2;
  double temperature;

  // Rocks
  final int ROCKS_TO_ADD;
  final float MIN_ROCK_ENERGY_BASE = 0.8;
  final float MAX_ROCK_ENERGY_BASE = 1.6;
  final float ROCK_DENSITY = 5;
  final color ROCK_COLOR = color(0, 0, 0.5);
  ArrayList<SoftBody> rocks;

  // Saving
  int[] fileSaveCounts;
  double[] fileSaveTimes;
  double imageSaveInterval = 1;
  double textSaveInterval = 1;

  // Misc or Unsorted
  final color BACKGROUND_COLOR = color(0, 0, 0.1);
  color buttonColor = color(0.82, 0.8, 0.7);
  String folder = "TEST";
  final double FLASH_SPEED = 80;
  boolean userControl;

  final String[] sorts = {"Biggest", "Smallest", "Youngest", "Oldest", "A to Z", "Z to A", "Highest Gen", "Lowest Gen"};

  @Override
  public float getStrokeWeight() {
    return CREATURE_STROKE_WEIGHT;
  }

  public Board(int w, int h, float stepSize, float min, float max, int rta, int cm, int SEED, String INITIAL_FILE_NAME, double ts) {
    noiseSeed(SEED);
    randomSeed(SEED);
    boardWidth = w;
    boardHeight = h;
    tiles = new Tile[w][h];
    for (int x = 0; x < boardWidth; x++) {
      for (int y = 0; y < boardHeight; y++) {
        float bigForce = pow(((float)y) / boardHeight, 0.5);
        float fertility = noise(x * stepSize * 3, y * stepSize * 3) * (1 - bigForce) * 5.0 + noise(x * stepSize * 0.5, y * stepSize * 0.5) * bigForce * 5.0 - 1.5;
        float climateType = noise(x * stepSize * 0.2 + 10000, y * stepSize * 0.2 + 10000) * 1.63 - 0.4;
        climateType = min(max(climateType, 0), 0.8);
        tiles[x][y] = new Tile(x, y, fertility, 0, climateType, this);
      }
    }
    MIN_TEMPERATURE = min;
    MAX_TEMPERATURE = max;

    softBodiesInPositions = new ArrayList[boardWidth][boardHeight];
    for (int x = 0; x < boardWidth; x++) {
      for (int y = 0; y < boardHeight; y++) {
        softBodiesInPositions[x][y] = new ArrayList<SoftBody>(0);
      }
    }

    ROCKS_TO_ADD = rta;
    rocks = new ArrayList<SoftBody>(0);
    for (int i = 0; i < ROCKS_TO_ADD; i++) {
      rocks.add(new SoftBody(generateUniqueId(), new Vector2D().set(random(0, boardWidth), random(0, boardHeight)), new Vector2D(), 
        getRandomSize(), ROCK_DENSITY, hue(ROCK_COLOR), saturation(ROCK_COLOR), brightness(ROCK_COLOR), this, year));
    }

    creatureMinimum = cm;
    maintainCreatureMinimum(false);
    for (int i = 0; i < LIST_SLOTS; i++) {
      list[i] = null;
    }
    folder = INITIAL_FILE_NAME;
    fileSaveCounts = new int[4];
    fileSaveTimes = new double[4];
    for (int i = 0; i < 4; i++) {
      fileSaveCounts[i] = 0;
      fileSaveTimes[i] = -999;
    }
    userControl = true;
    timeStep = ts;
    populationHistory = new int[POPULATION_HISTORY_LENGTH];
    for (int i = 0; i < POPULATION_HISTORY_LENGTH; i++) {
      populationHistory[i] = 0;
    }
    
    workDistributor = new WorkDistributor(creatures);
    for (int i = 0; i < WORKER_THREAD_COUNT; i++) {
      final Thread newThread = new CreatureWorkerThread(workDistributor);
      newThread.start();
      workerThreads.add(newThread);
    }
  }
  
  @Override
  public int getBoardWidth() {
    return boardWidth;
  }
  
  @Override
  public int getBoardHeight() {
    return boardHeight;
  }
  
  @Override
  public color getBackgroundColor() {
    return BACKGROUND_COLOR;
  }
  
  @Override
  public color getTileColor(Vector2D pos) {
    if (pos.getX() >= 0 && pos.getX() < boardWidth && pos.getY() >= 0 && pos.getY() < boardHeight) {
      return tiles[(int) pos.getX()][(int) pos.getY()].getColor();
    } else {
      return BACKGROUND_COLOR;
    }
  }
  
  @Override
  public synchronized List<SoftBody> getSoftBodiesAtPosition(Vector2D pos) {
    final int tileX = (int) pos.getX();
    final int tileY = (int) pos.getY();
    
    if (tileX >= 0 && tileX < boardWidth && tileY >= 0 && tileY < boardHeight) {
      return softBodiesInPositions[tileX][tileY];
    }
    return EMPTY_SOFT_BODY_LIST;
  }
  
  @Override
  public boolean interactWithTileAtLocation(Vector2D pos, SynchronizedTileInteraction handler) {
    final int tileX = (int) pos.getX();
    final int tileY = (int) pos.getY();
    
    if (tileX >= 0 && tileX < boardWidth && tileY >= 0 && tileY < boardHeight) {
      final Tile tile = tiles[tileX][tileY];
      synchronized (tile) {
        handler.handleTile(tile);
      }
      return true;
    } else {
      return false;
    }
  }


  public synchronized void stop() {
    try {
      for (Thread thread : workerThreads) {
        if (thread.isAlive()) {
          thread.interrupt();
          thread.join();
        }
      }
    }
    catch (InterruptedException e) {
      Thread.currentThread().interrupt();
    }
  }
  
  public synchronized void drawBoard(float scaleUp, float camZoom, int mX, int mY) {
    for (int x = 0; x < boardWidth; x++) {
      for (int y = 0; y < boardHeight; y++) {
        tiles[x][y].drawTile(scaleUp, (mX == x && mY == y));
      }
    }
    for (final SoftBody sb : rocks) {
      sb.drawSoftBody(this, false, scaleUp, camZoom, true);
    }
    for (final Creature c : creatures) {
      c.drawSoftBody(this, c == selectedCreature, scaleUp, camZoom, true);
    }
  }

  public synchronized void drawBlankBoard(float scaleUp) {
    fill(BACKGROUND_COLOR);
    rect(0, 0, scaleUp * boardWidth, scaleUp * boardHeight);
  }

  public synchronized void drawUI(float scaleUp, float camZoom, double timeStep, int x1, int y1, int x2, int y2, PFont font) {
    fill(0, 0, 0);
    noStroke();
    rect(x1, y1, x2 - x1, y2 - y1);

    pushMatrix();
    translate(x1, y1);

    fill(0, 0, 1);
    textAlign(RIGHT);
    text(nfs(camZoom * 100, 0, 3) + " %", 0, y2 - y1 - 30);
    textAlign(LEFT);
    textFont(font, 48);
    String yearText = "Year "+nf((float)year, 0, 2);
    text(yearText, 10, 48);
    float seasonTextXCoor = textWidth(yearText) + 50;
    textFont(font, 24);
    text("Population: " + creatures.size(), 10, 80);
    String[] seasons = {"Winter", "Spring", "Summer", "Autumn"};
    text(seasons[(int)(getSeason() * 4)] + "\nSeed: " + SEED, seasonTextXCoor, 30);

    if (selectedCreature == null) {
      for (int i = 0; i < LIST_SLOTS; i++) {
        list[i] = null;
      }
      for (int i = 0; i < creatures.size(); i++) {
        int lookingAt = 0;
        boolean done = false;
        while (lookingAt < LIST_SLOTS && list[lookingAt] != null & !done) {
          if (creatureRankMetric == 4 && list[lookingAt].name.compareTo(creatures.get(i).name) < 0) {
              lookingAt++;
          } else if (creatureRankMetric == 5 && list[lookingAt].name.compareTo(creatures.get(i).name) >= 0) {
              lookingAt++;
          } else if (list[lookingAt].measure(creatureRankMetric) > creatures.get(i).measure(creatureRankMetric)) {
              lookingAt++;
          } else {
            done = true;
          }
        }

        if (lookingAt < LIST_SLOTS) {
          for (int j = LIST_SLOTS - 1; j >= lookingAt + 1; j--) {
            list[j] = list[j - 1];
          }
          list[lookingAt] = creatures.get(i);
        }
      }
      double maxEnergy = 0;
      for (int i = 0; i < LIST_SLOTS; i++) {
        if (list[i] != null && list[i].energy > maxEnergy) {
          maxEnergy = list[i].energy;
        }
      }
      for (int i = 0; i < LIST_SLOTS; i++) {
        if (list[i] != null) {
          list[i].preferredRank += (i - list[i].preferredRank) * 0.4;
          float y = y1 + 175 + 70 * list[i].preferredRank;
          drawCreature(list[i], 45, y + 5, 2.3, scaleUp);
          textFont(font, 24);
          textAlign(LEFT);
          noStroke();
          fill(0.333, 1, 0.4);
          float multi = (x2 - x1 - 200);
          if (list[i].energy > 0) {
            rect(85, y + 5, (float)(multi * list[i].energy / maxEnergy), 25);
          }
          if (list[i].energy > 1) {
            fill(0.333, 1, 0.8);
            rect(85+(float)(multi / maxEnergy), y + 5, (float)(multi * (list[i].energy - 1) / maxEnergy), 25);
          }
          fill(0, 0, 1);
          text(list[i].getCreatureName() + " [" + list[i].getId() + "] (" + toAge(list[i].birthTime) + ")", 90, y);
          text("Energy: " + nf(100 * (float)(list[i].energy), 0, 2), 90, y + 25);
        }
      }
      noStroke();
      fill(buttonColor);
      rect(10, 95, 220, 40);
      rect(240, 95, 220, 40);
      fill(0, 0, 1);
      textAlign(CENTER);
      text("Reset zoom", 120, 123);
      text("Sort by: " + sorts[creatureRankMetric], 350, 123);

      textFont(font, 19);
      String[] buttonTexts = {"Brain Control", "Maintain pop. at " + creatureMinimum,
        "Screenshot now", "-   Image every " + nf((float)imageSaveInterval, 0, 2) + " years   +",
        "Text file now", "-    Text every " + nf((float)textSaveInterval, 0, 2) + " years    +",
        "-    Play Speed (" + playSpeed + "x)    +", "This button does nothing"};
      if (userControl) {
        buttonTexts[0] = "Keyboard Control";
      }
      for (int i = 0; i < 8; i++) {
        float x = (i % 2) * 230 + 10;
        float y = floor(i / 2) * 50 + 570;
        fill(buttonColor);
        rect(x, y, 220, 40);
        if (i >= 2 && i < 6) {
          double flashAlpha = 1.0 * Math.pow(0.5, (year - fileSaveTimes[i - 2]) * FLASH_SPEED);
          fill(0, 0, 1, (float)flashAlpha);
          rect(x, y, 220, 40);
        }
        fill(0, 0, 1, 1);
        text(buttonTexts[i], x + 110, y + 17);
        if (i == 0) {
        } else if (i == 1) {
          text("-" + creatureMinimumIncrement + "                    +" + creatureMinimumIncrement, x + 110, y + 37);
        } else if (i <= 5) {
          text(getNextFileName(i - 2), x + 110, y + 37);
        }
      }
    } else {
      float energyUsage = (float)selectedCreature.getEnergyUsage(timeStep);
      noStroke();
      if (energyUsage <= 0) {
        fill(0, 1, 0.5);
      } else {
        fill(0.33, 1, 0.4);
      }
      float EUbar = 20 * energyUsage;
      rect(110, 280, min(max(EUbar, -110), 110), 25);
      if (EUbar < -110) {
        rect(0, 280, 25, (-110 - EUbar) * 20 + 25);
      } else if (EUbar > 110) {
        float h = (EUbar-110) * 20 + 25;
        rect(185, 280-h, 25, h);
      }
      fill(0, 0, 1);
      
      int linePos = 225;
      text("Name: " + selectedCreature.getCreatureName(), 10, linePos); linePos += 25;
      text("Energy: " + nf(100 * (float)selectedCreature.energy, 0, 2) + " yums", 10, linePos); linePos += 25;
      text("E Change: " + nf(100 * energyUsage, 0, 2) + " yums/year", 10, linePos); linePos += 25;

      text("ID: " + selectedCreature.getId(), 10, linePos); linePos += 25;
      text("Pos: " + selectedCreature.getPosition(), 10, linePos); linePos += 25;
      text("Rotation: " + nf((float)selectedCreature.rotation, 0, 2), 10, linePos); linePos += 25;
      text("B-day: " + toDate(selectedCreature.birthTime), 10, linePos); linePos += 25;
      text("(" + toAge(selectedCreature.birthTime) + ")", 10, linePos); linePos += 25;
      text("Generation: " + selectedCreature.gen, 10, linePos); linePos += 25;
      text("Parents: " + selectedCreature.parents, 10, linePos, 210, 255); linePos += 25 * 2;
      text("Hue: " + nf((float)(selectedCreature.hue), 0, 2), 10, linePos, 210, 255); linePos += 25;
      text("Mouth hue: " + nf((float)(selectedCreature.mouthHue), 0, 2), 10, linePos, 210, 255); linePos += 25;

      if (userControl) {
        linePos += 25;
        text("Controls:\nUp/Down: Move\nLeft/Right: Rotate\nSpace: Eat\nF: Fight\nV: Vomit\nU, J: Change color"+
          "\nI, K: Change mouth color\nB: Give birth (Not possible if under " + Math.round((MANUAL_BIRTH_SIZE + 1) * 100) + " yums)", 10, linePos, 250, 400);
      }
      pushMatrix();
      translate(400, 80);
      float apX = round((mouseX - 400 - x1) / 46.0);
      float apY = round((mouseY - 80 - y1) / 46.0);
      selectedCreature.drawBrain(font, 46, (int)apX, (int)apY);
      popMatrix();
    }
    drawPopulationGraph(x1, x2, y1, y2);
    fill(0, 0, 0);
    textAlign(RIGHT);
    textFont(font, 24);
    text("Population: " + creatures.size(), x2 - x1 - 10, y2 - y1 - 10);
    popMatrix();

    pushMatrix();
    translate(x2, y1);
    textAlign(RIGHT);
    textFont(font, 24);
    text("Temperature", -10, 24);
    drawThermometer(-45, 30, 20, 660, temperature, THERMOMETER_MIN, THERMOMETER_MAX, color(0, 1, 1));
    popMatrix();

    if (selectedCreature != null) {
      drawCreature(selectedCreature, x1 + 65, y1 + 147, 2.3, scaleUp);
    }
  }

  private synchronized void drawPopulationGraph(float x1, float x2, float y1, float y2) {
    float barWidth = (x2 - x1) / ((float)(POPULATION_HISTORY_LENGTH));
    noStroke();
    fill(0.33333, 1, 0.6);
    int maxPopulation = 0;
    for (int i = 0; i < POPULATION_HISTORY_LENGTH; i++) {
      if (populationHistory[i] > maxPopulation) {
        maxPopulation = populationHistory[i];
      }
    }
    for (int i = 0; i < POPULATION_HISTORY_LENGTH; i++) {
      float h = (((float)populationHistory[i]) / maxPopulation) * (y2 - 770);
      rect((POPULATION_HISTORY_LENGTH - 1 - i) * barWidth, y2 - h, barWidth, h);
    }
  }

  public synchronized String getNextFileName(int type) {
    String[] modes = {"manualImgs", "autoImgs", "manualTexts", "autoTexts"};
    String ending = ".png";
    if (type >= 2) {
      ending = ".txt";
    }
    return folder + "/" + modes[type] + "/" + nf(fileSaveCounts[type], 5) + ending;
  }

  public synchronized int generateUniqueId() {
    return uniqueIdCounter++;
  };
  
  @Override
  public synchronized void addCreature(Creature newCreature) {
    newCreatures.add(newCreature);
  }

  private boolean isIterating = false;
  private StopWatch iterationStartSW = new StopWatch("iteration start");
  private StopWatch iterationSimSW = new StopWatch("iteration simulation");
  private StopWatch iterationEndSW = new StopWatch("iteration end");
  
  private StopWatch iterationEndRemoveLoopSW = new StopWatch("iteration end remove loop");
  private StopWatch iterationEndFinishSW = new StopWatch("iteration end finish func");
  public void iterate(double timeStep) {
    iterationStartSW.start();
    
    synchronized (this) {
      try {
        while (isIterating) {
          wait();
        }
      }
      catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        return;
      }
      isIterating = true;
      
      double prevYear = year;
      year += timeStep;
      if (Math.floor(year / recordPopulationEvery) != Math.floor(prevYear / recordPopulationEvery)) {
        for (int i = POPULATION_HISTORY_LENGTH - 1; i >= 1; i--) {
          populationHistory[i] = populationHistory[i - 1];
        }
        populationHistory[0] = creatures.size();
      }
      temperature = getGrowthRate(getSeason());
      double tempChangeIntoThisFrame = temperature - getGrowthRate(getSeason() - timeStep);
      double tempChangeOutOfThisFrame = getGrowthRate(getSeason() + timeStep) - temperature;
      if (tempChangeIntoThisFrame * tempChangeOutOfThisFrame <= 0) { // Temperature change flipped direction.
        for (int x = 0; x < boardWidth; x++) {
          for (int y = 0; y < boardHeight; y++) {
            tiles[x][y].iterate();
          }
        }
      }
      /*for(int x = 0; x < boardWidth; x++) {
       for(int y = 0; y < boardHeight; y++) {
       tiles[x][y].iterate(this, year);
       }
       }*/
      for (final Creature creature : creatures) {
        creature.setPreviousEnergy();
      }
      /*for(int i = 0; i < rocks.size(); i++) {
       rocks.get(i).collide(timeStep*OBJECT_TIMESTEPS_PER_YEAR);
       }*/
       
      // Fillup creature pool (first with children, then with new creatures)
      mergeNewCreaturePool();
      maintainCreatureMinimum(false);
    }
    //iterationStartSW.lap();
    
    iterationSimSW.start();
    if (userControl) {
      if (selectedCreature != null) {
        if (keyPressed) {
          if (key == CODED) {
            if (keyCode == UP) selectedCreature.accelerate(0.04, timeStep * OBJECT_TIMESTEPS_PER_YEAR);
            if (keyCode == DOWN) selectedCreature.accelerate(-0.04, timeStep * OBJECT_TIMESTEPS_PER_YEAR);
            if (keyCode == LEFT) selectedCreature.turn(-0.1, timeStep * OBJECT_TIMESTEPS_PER_YEAR);
            if (keyCode == RIGHT) selectedCreature.turn(0.1, timeStep * OBJECT_TIMESTEPS_PER_YEAR);
          } else {
            if (key == ' ') selectedCreature.eat(0.1, timeStep * OBJECT_TIMESTEPS_PER_YEAR);
            if (key == 'v' || key == 'V') selectedCreature.eat(-0.1, timeStep * OBJECT_TIMESTEPS_PER_YEAR);
            if (key == 'f' || key == 'F')  selectedCreature.fight(0.5, timeStep * OBJECT_TIMESTEPS_PER_YEAR, year);
            if (key == 'u' || key == 'U') selectedCreature.setHue(selectedCreature.hue + 0.02);
            if (key == 'j' || key == 'J') selectedCreature.setHue(selectedCreature.hue - 0.02);

            if (key == 'i' || key == 'I') selectedCreature.setMouthHue(selectedCreature.mouthHue + 0.02);
            if (key == 'k' || key == 'K') selectedCreature.setMouthHue(selectedCreature.mouthHue - 0.02);
            if (key == 'b' || key == 'B') {
              if (!wasPressingB) {
                selectedCreature.reproduce(MANUAL_BIRTH_SIZE, timeStep, year);
              }
              wasPressingB = true;
            } else {
              wasPressingB = false;
            }
          }
          
          selectedCreature.collide(timeStep);
          selectedCreature.metabolize(timeStep, year);
          selectedCreature.useBrain(timeStep, !userControl, Board.this.year);
        }
      }
      
      for (final Creature creature : creatures) {
        creature.see(timeStep);
      }
    } else {
      workDistributor.cycle();
    }
    //iterationSimSW.lap();

    iterationEndSW.start();
    synchronized (this) {
      iterationEndRemoveLoopSW.start();
      
      final Iterator<Creature> creatureIterator = creatures.iterator(); 
      while (creatureIterator.hasNext()) {
        final Creature me = creatureIterator.next();
        if (me.getRadius() < MINIMUM_SURVIVABLE_SIZE) {
          if (selectedCreature == me) {
            unselect();
          }
          
          me.returnToEarth();

          for (int x = SBIPMinX; x <= SBIPMaxX; x++) {
            for (int y = SBIPMinY; y <= SBIPMaxY; y++) {
              board.softBodiesInPositions[x][y].remove(this);
            }
          }
          
          creatureIterator.remove();
        }
      }
      //iterationEndRemoveLoopSW.lap();

      iterationEndFinishSW.start();
      finishIterate(timeStep);
      //iterationEndFinishSW.lap();
      
      isIterating = false;
      notify();
    }

    //iterationEndSW.lap();
  }

  public synchronized void finishIterate(double timeStep) {
    for (final SoftBody rock : rocks) {
      rock.applyMotions(timeStep * OBJECT_TIMESTEPS_PER_YEAR);
    }
    for (final Creature creature : creatures) {
      creature.applyMotions(timeStep * OBJECT_TIMESTEPS_PER_YEAR);
    }
    
    /*
    if (Math.floor(fileSaveTimes[1] / imageSaveInterval) != Math.floor(year / imageSaveInterval)) {
      prepareForFileSave(1);
    }
    if (Math.floor(fileSaveTimes[3] / textSaveInterval) != Math.floor(year / textSaveInterval)) {
      prepareForFileSave(3);
    }*/
  }

  private double getGrowthRate(double theTime) {
    double temperatureRange = MAX_TEMPERATURE - MIN_TEMPERATURE;
    return MIN_TEMPERATURE + temperatureRange * 0.5 - temperatureRange * 0.5 * Math.cos(theTime * 2 * Math.PI);
  }

  private double getGrowthOverTimeRange(double startTime, double endTime) {
    double temperatureRange = MAX_TEMPERATURE - MIN_TEMPERATURE;
    double m = MIN_TEMPERATURE + temperatureRange * 0.5;
    return (endTime - startTime) * m + (temperatureRange / Math.PI / 4.0) * (Math.sin(2 * Math.PI * startTime) - Math.sin(2 * Math.PI * endTime));
  }

  private double getSeason() {
    return (year % 1.0);
  }

  private synchronized void drawThermometer(float x1, float y1, float w, float h, double prog, double min, double max, 
    color fillColor) {
    noStroke();
    fill(0, 0, 0.2);
    rect(x1, y1, w, h);
    fill(fillColor);
    double proportionFilled = (prog - min) / (max - min);
    rect(x1, (float)(y1 + h * (1 - proportionFilled)), w, (float)(proportionFilled * h));


    double zeroHeight = (0 - min) / (max - min);
    double zeroLineY = y1 + h * (1 - zeroHeight);
    textAlign(RIGHT);
    stroke(0, 0, 1);
    strokeWeight(3);
    line(x1, (float)(zeroLineY), x1 + w, (float)(zeroLineY));
    double minY = y1 + h * (1 - (MIN_TEMPERATURE - min) / (max - min));
    double maxY = y1 + h * (1 - (MAX_TEMPERATURE - min) / (max - min));
    fill(0, 0, 0.8);
    line(x1, (float)(minY), x1 + w * 1.8, (float)(minY));
    line(x1, (float)(maxY), x1 + w * 1.8, (float)(maxY));
    line(x1+w*1.8, (float)(minY), x1 + w * 1.8, (float)(maxY));

    fill(0, 0, 1);
    text("Zero", x1 - 5, (float)(zeroLineY + 8));
    text(nf(MIN_TEMPERATURE, 0, 2), x1 - 5, (float)(minY + 8));
    text(nf(MAX_TEMPERATURE, 0, 2), x1 - 5, (float)(maxY + 8));
  }

  private void drawVerticalSlider(float x1, float y1, float w, float h, double prog, color fillColor, color antiColor) {
    noStroke();
    fill(0, 0, 0.2);
    rect(x1, y1, w, h);
    if (prog >= 0) {
      fill(fillColor);
    } else {
      fill(antiColor);
    }
    rect(x1, (float)(y1 + h * (1 - prog)), w, (float)(prog * h));
  }

  private boolean setMinTemperature(float temp) {
    MIN_TEMPERATURE = tempBounds(THERMOMETER_MIN + temp * (THERMOMETER_MAX - THERMOMETER_MIN));
    if (MIN_TEMPERATURE > MAX_TEMPERATURE) {
      float placeHolder = MAX_TEMPERATURE;
      MAX_TEMPERATURE = MIN_TEMPERATURE;
      MIN_TEMPERATURE = placeHolder;
      return true;
    }
    return false;
  }

  private boolean setMaxTemperature(float temp) {
    MAX_TEMPERATURE = tempBounds(THERMOMETER_MIN + temp * (THERMOMETER_MAX - THERMOMETER_MIN));
    if (MIN_TEMPERATURE > MAX_TEMPERATURE) {
      float placeHolder = MAX_TEMPERATURE;
      MAX_TEMPERATURE = MIN_TEMPERATURE;
      MIN_TEMPERATURE = placeHolder;
      return true;
    }
    return false;
  }

  private float tempBounds(float temp) {
    return min(max(temp, THERMOMETER_MIN), THERMOMETER_MAX);
  }

  private float getHighTempProportion() {
    return (MAX_TEMPERATURE - THERMOMETER_MIN) / (THERMOMETER_MAX - THERMOMETER_MIN);
  }

  private float getLowTempProportion() {
    return (MIN_TEMPERATURE - THERMOMETER_MIN) / (THERMOMETER_MAX - THERMOMETER_MIN);
  }

  private String toDate(double d) {
    return "Year " + nf((float)(d), 0, 2);
  }

  private String toAge(double d) {
    return nf((float)(year - d), 0, 2) + " yrs old";
  }

  private synchronized void mergeNewCreaturePool() {
    this.creatures.addAll(this.newCreatures);
    this.newCreatures.clear();
  }

  private void maintainCreatureMinimum(boolean choosePreexisting) {
    while ((newCreatures.size() + creatures.size()) < creatureMinimum) {
      if (choosePreexisting) {
        Creature c = getRandomCreature();
        c.addEnergy(c.SAFE_SIZE);
        c.reproduce(c.SAFE_SIZE, timeStep, year);
      } else {
        creatures.add(new Creature(generateUniqueId(), new Vector2D().set(random(0, boardWidth), random(0, boardHeight)), new Vector2D(), 
          random(MIN_CREATURE_ENERGY, MAX_CREATURE_ENERGY), 1, random(0, 1), 1, 1, 
          this, year, random(0, 2 * PI), 0, "", "[PRIMORDIAL]", true, null, 1, random(0, 1)));
      }
    }
    mergeNewCreaturePool();
  }

  private Creature getRandomCreature() {
    int index = (int)(random(0, creatures.size()));
    return creatures.get(index);
  }

  private double getRandomSize() {
    return pow(random(MIN_ROCK_ENERGY_BASE, MAX_ROCK_ENERGY_BASE), 4);
  }

  private void drawCreature(Creature c, float x, float y, float scale, float scaleUp) {
    pushMatrix();
    float scaleIconUp = scaleUp * scale;
    final Vector2D creaturePos = c.getPosition();
    translate((float)(-creaturePos.getX() * scaleIconUp), (float)(-creaturePos.getY() * scaleIconUp));
    translate(x, y);
    c.drawSoftBody(this, c == selectedCreature, scaleIconUp, 40.0 / scale, false);
    popMatrix();
  }

  private void prepareForFileSave(int type) {
    fileSaveTimes[type] = -999999;
  }

  private void fileSave() {
    for (int i = 0; i < 4; i++) {
      if (fileSaveTimes[i] < -99999) {
        fileSaveTimes[i] = year;
        if (i < 2) {
          saveFrame(getNextFileName(i));
        } else {
          String[] data = this.toBigString();
          saveStrings(getNextFileName(i), data);
        }
        fileSaveCounts[i]++;
      }
    }
  }
  
  public synchronized void incrementSort() {
    evoBoard.creatureRankMetric = (evoBoard.creatureRankMetric + 1) % sorts.length;
  }
  
  public synchronized void decrementSort() {
    evoBoard.creatureRankMetric = (evoBoard.creatureRankMetric + sorts.length - 1) % sorts.length;
  }

  public String[] toBigString() { // Convert current evolvio board into string. Does not work
    String[] placeholder = {"Goo goo", "Ga ga"};
    return placeholder;
  }

  public void unselect() {
    selectedCreature = null;
  }
}