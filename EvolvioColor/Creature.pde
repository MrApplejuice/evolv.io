static NameGenerator nameGenerator = null;
{
  synchronized (this) {
    if (nameGenerator == null) {
      nameGenerator = new NameGenerator();
    }
  }
}

class Creature extends SoftBody implements OrientedBody {
  public static final double BRIGHTNESS_THRESHOLD = 0.7;
  
  // Energy
  public static final double ACCELERATION_ENERGY = 0.18;
  public static final double ACCELERATION_BACK_ENERGY = 0.24;
  public static final double SWIM_ENERGY = 0.008;
  public static final double TURN_ENERGY = 0.05;
  public static final double EAT_ENERGY = 0.05;
  public static final double EAT_SPEED = 0.5; // 1 is instant, 0 is nonexistent, 0.001 is verrry slow.
  public static final double EAT_WHILE_MOVING_INEFFICIENCY_MULTIPLIER = 2.0; // The bigger this number is, the less effiently creatures eat when they're moving.
  public static final double FIGHT_ENERGY = 0.06;
  public static final double INJURED_ENERGY = 0.25;
  public static final double METABOLISM_ENERGY = 0.004;
  public static final double AGE_FACTOR = 1; // 0 no ageing
  public static final double SAFE_SIZE = 1.25;
  public static final double MATURE_AGE = 0.01;
  public static final double FOOD_SENSITIVITY = 0.3;
  public static final double MAX_DETAILED_ZOOM = 3.5; // Maximum zoom to draw details at
  public static final int ENERGY_HISTORY_LENGTH = 6;
  public static final float CROSS_SIZE = 0.022;

  private double[] previousEnergy = new double[ENERGY_HISTORY_LENGTH];

  // Family
  private String name;
  private String parents;
  private int gen;
  
  private List<Creature> parentsList = new ArrayList<Creature>();

  // Vision or View or Preference
  private VisionSystem visionSystem = new VisionSystem(softBodyLinAlgPool);
  private Brain brain;

  private float preferredRank = 8;
  private double mouthHue;
  private double vr = 0;
  private double rotation = 0;
  private double fightLevel = 0;

  private double plannedReproductionValue = 0;
  private double plannedFightValue = 0;
  
  
  public double getRotation() {
    return rotation;
  }

  public Creature(int id, Vector2D pos, Vector2D vel, double tenergy, 
    double tdensity, double thue, double tsaturation, double tbrightness, AbstractBoardInterface tb, double bt, 
    double rot, double tvr, String tname, String tparents, boolean mutateName, 
    Brain brain, int tgen, double tmouthHue) {

    super(id, pos, vel, tenergy, tdensity, thue, tsaturation, tbrightness, tb, bt);

    if (brain == null) {
      brain = new Brain(null, null);
    }
    this.brain = brain;

    rotation = rot;
    vr = tvr;
    if (tname.length() >= 1) {
      if (mutateName) {
        name = nameGenerator.mutateName(tname);
      } else {
        name = tname;
      }
      name = nameGenerator.sanitizeName(name);
    } else {
      name = nameGenerator.newName();
    }
    parents = tparents;
    gen = tgen;
    mouthHue = tmouthHue;
  }

  /////////////////// DRAW FUNCTIONS /////////////////
 
  public void drawBrain(PFont font, float scaleUp, int mX, int mY) {
    brain.draw(font, scaleUp, mX, mY);
  }

  @Override
  public void drawSoftBody(DrawConfiguration drawConfig, boolean isSelected, float scaleUp, float camZoom, boolean showVision) {
    ellipseMode(RADIUS);
    double radius = getRadius();
    if (showVision && camZoom > MAX_DETAILED_ZOOM) {
      drawVisionAngles(drawConfig, scaleUp);
    }
    noStroke();
    if (fightLevel > 0) {
      fill(0, 1, 1, (float)(fightLevel * 0.8));
      ellipse((float)(position.getX() * scaleUp), (float)(position.getY() * scaleUp), (float)(FIGHT_RANGE * radius * scaleUp), (float)(FIGHT_RANGE * radius * scaleUp));
    }
    strokeWeight(Board.CREATURE_STROKE_WEIGHT);
    stroke(0, 0, 1);
    fill(0, 0, 1);
    if (isSelected) {
      ellipse((float)(position.getX() * scaleUp), (float)(position.getY() * scaleUp), 
        (float)(radius * scaleUp + 1 + 75.0 / camZoom), (float)(radius * scaleUp + 1 + 75.0 / camZoom));
    }
    super.drawSoftBody(drawConfig, isSelected, scaleUp, camZoom, showVision);

    if (camZoom > MAX_DETAILED_ZOOM) {
      drawMouth(scaleUp, radius, rotation, camZoom, mouthHue);
      if (showVision) {
        fill(0, 0, 1);
        textFont(font, 0.2 * scaleUp);
        textAlign(CENTER);
        text(getCreatureName(), (float)(position.getX() * scaleUp), (float)((position.getY() - getRadius() * 1.4 - 0.07) * scaleUp));
      }
    }
  }

  public void drawVisionAngles(DrawConfiguration drawConfig, float scaleUp) {
    double[] visionValues = visionSystem.getValues();
    Vector2D[] visionEndpoints = visionSystem.getVisionEndpoints();
    Vector2D[] visionRangePoints = visionSystem.getVisionRangePoints();
    for (int i = 0; i < visionRangePoints.length; i++) {
      color visionUIcolor = color(0, 0, 1);
      if (visionValues[i * 3 + 2] > BRIGHTNESS_THRESHOLD) {
        visionUIcolor = color(0, 0, 0);
      }
      stroke(visionUIcolor);
      strokeWeight(drawConfig.getStrokeWeight());
      line((float)(position.getX() * scaleUp), (float) (position.getY() * scaleUp), (float) (visionRangePoints[i].getX() * scaleUp), (float) (visionRangePoints[i].getY() * scaleUp));
      noStroke();
      fill(visionUIcolor);
      ellipse((float)(visionEndpoints[i].getX() * scaleUp), (float)(visionEndpoints[i].getY() * scaleUp), 2 * CROSS_SIZE * scaleUp, 2 * CROSS_SIZE * scaleUp);

      fill((float) (visionValues[i * 3]), (float) (visionValues[i * 3 + 1]), (float) (visionValues[i * 3 + 2]));
      ellipse((float)(visionEndpoints[i].getX() * scaleUp), (float)(visionEndpoints[i].getY() * scaleUp), CROSS_SIZE * scaleUp, CROSS_SIZE * scaleUp);
    }
  }
  
  public void drawMouth(float scaleUp, double radius, double rotation, float camZoom, double mouthHue) {
    noFill();
    strokeWeight(Board.CREATURE_STROKE_WEIGHT);
    stroke(0, 0, 1);
    ellipseMode(RADIUS);
    ellipse((float)(position.getX() * scaleUp), (float)(position.getY() * scaleUp), 
      (float) (Board.MINIMUM_SURVIVABLE_SIZE * scaleUp), (float) (Board.MINIMUM_SURVIVABLE_SIZE * scaleUp));
    pushMatrix();
    translate((float)(position.getX() * scaleUp), (float)(position.getY() * scaleUp));
    scale((float)radius);
    rotate((float)rotation);
    strokeWeight((float)(Board.CREATURE_STROKE_WEIGHT / radius));
    stroke(0, 0, 0);
    fill((float)mouthHue, 1.0, 1.0);
    ellipse(0.6 * scaleUp, 0, 0.37 * scaleUp, 0.37 * scaleUp);
    popMatrix();
  }

  //////////////////// SIMULATION FUNCTIONS ////////////////////

  public void useBrain(double timeStep, boolean useOutput) {
    double inputs[] = new double[11];
    
    double[] visionValues = visionSystem.getValues();
    for (int i = 0; i < 9; i++) {
      inputs[i] = visionValues[i];
    }
    inputs[9] = energy;
    inputs[10] = mouthHue;
    brain.input(inputs);
    
    if (useOutput) {
      double[] output = brain.outputs();
      hue = Math.abs(output[0]) % 1.0;
      accelerate(output[1], timeStep);
      turn(output[2], timeStep);
      eat(output[3], timeStep);
      fight(output[4]);
      if (output[5] > 0 && board.getCurrentYear() - birthTime >= MATURE_AGE && energy > SAFE_SIZE) {
        reproduce(SAFE_SIZE);
      }
      mouthHue = Math.abs(output[10]) % 1.0;
    }
  }

  @Override //<>//
  public void collide(double timeStep, List<SoftBody> colliders) {
    super.collide(timeStep, colliders);
    
    if (plannedReproductionValue > 0) {
      doReproduce(colliders, plannedReproductionValue);
      plannedReproductionValue = 0;
    }
    if (plannedFightValue > 0) {
      doFight(colliders, plannedFightValue, timeStep);
      plannedFightValue = 0;
    }
  }
  
  public void metabolize(double timeStep, double currentYear) {
    double age = AGE_FACTOR * (currentYear - birthTime); // the older the more work necessary
    loseEnergy(energy * METABOLISM_ENERGY * age * timeStep);
  }

  public void accelerate(double amount, double timeStep) {
    double multiplied = amount * timeStep / getMass();
    
    final Vector2D deltaV = softBodyLinAlgPool.getVector2D().set(Math.cos(rotation) * multiplied, Math.sin(rotation) * multiplied);
    velocity.inplaceAdd(deltaV);
    softBodyLinAlgPool.recycle(deltaV);
    
    if (amount >= 0) {
      loseEnergy(amount * ACCELERATION_ENERGY * timeStep);
    } else {
      loseEnergy(Math.abs(amount * ACCELERATION_BACK_ENERGY * timeStep));
    }
  }

  public void turn(double amount, double timeStep) {
    vr += 0.04 * amount * timeStep / getMass();
    loseEnergy(Math.abs(amount * TURN_ENERGY * energy * timeStep));
  }
  
  public void eat(final double attemptedAmount, final double timeStep) {
    final double amount = attemptedAmount / (1.0 + velocity.length() * EAT_WHILE_MOVING_INEFFICIENCY_MULTIPLIER); // The faster you're moving, the less efficiently you can eat.
    if (amount < 0) {
      dropEnergy(-amount * timeStep);
      loseEnergy(-attemptedAmount * EAT_ENERGY * timeStep);
    } else {
      final Vector2D tileLocation = getRandomCoveredTileLocation();

      final SettableDouble foodToEat = new SettableDouble();
      final SettableDouble foodDistance = new SettableDouble();
      board.interactWithTileAtLocation(tileLocation, new SynchronizedTileInteraction() {
        @Override
        public void handleTile(Tile tile) {
          double _foodToEat = tile.foodLevel * (1 - Math.pow((1 - EAT_SPEED), amount * timeStep));
          if (_foodToEat > tile.foodLevel) {
            _foodToEat = tile.foodLevel;
          }
          tile.removeFood(_foodToEat, true);

          foodToEat.value = _foodToEat;
          foodDistance.value = Math.abs(tile.foodType - mouthHue);
        }
      });
      
      softBodyLinAlgPool.recycle(tileLocation);
      
      double multiplier = 1.0 - foodDistance.value / FOOD_SENSITIVITY;
      if (multiplier >= 0) {
        addEnergy(foodToEat.value * multiplier);
      } else {
        loseEnergy(-foodToEat.value * multiplier);
      }
      loseEnergy(attemptedAmount * EAT_ENERGY * timeStep);
    }
  }

  public void fight(double amount) {
    plannedFightValue = amount;
  }
    
  protected void doFight(List<SoftBody> colliders, double amount, double timeStep) {
    if (amount > 0 && board.getCurrentYear() - birthTime >= MATURE_AGE) {
      fightLevel = amount * 100; // 100 copied from useBrain - kinda random?
      loseEnergy(fightLevel * FIGHT_ENERGY * energy * timeStep);
      for (final SoftBody collider : colliders) {
        if (Creature.class.isInstance(collider)) {
          final Creature colliderCreature = Creature.class.cast(collider);
          final double distance = position.distance(colliderCreature.getPosition());
          final double combinedRadius = getRadius() * FIGHT_RANGE + collider.getRadius();
          if (distance < combinedRadius) {
            colliderCreature.dropEnergy(fightLevel * INJURED_ENERGY * timeStep);
          }
        }
      }
    } else {
      fightLevel = 0;
    }
  }

  public void loseEnergy(double energyLost) {
    if (energyLost > 0) {
      energy -= energyLost;
    }
  }

  public void dropEnergy(double energyLost) {
    if (energyLost > 0) {
      final double realEnergyLost = Math.min(energyLost, energy);
      energy -= energyLost;
      
      final Vector2D tileLocation = getRandomCoveredTileLocation();
      board.interactWithTileAtLocation(tileLocation, new SynchronizedTileInteraction() {
        @Override
        public void handleTile(Tile tile) {
          tile.addFood(realEnergyLost, hue, true);
        }
      });
      softBodyLinAlgPool.recycle(tileLocation);
    }
  }

  public void see(double timeStep) {
    visionSystem.updateVision(board, position, getRotation(), this);
  }
  
  private Vector2D getRandomCoveredTileLocation() {
    double radius = getRadius();

    Vector2D choice = softBodyLinAlgPool.getVector2D().set(0, 0);
    
    while (choice.distance(position) > radius) {
      choice.set(Math.random() * 2 * radius - radius,
                 Math.random() * 2 * radius - radius);
      choice.inplaceAdd(position);
    }
    
    return choice;
  }

  public void returnToEarth() {
    final int pieces = 20;
    for (int i = 0; i < pieces; i++) {
      final Vector2D tileLocation = getRandomCoveredTileLocation();
      board.interactWithTileAtLocation(tileLocation, new SynchronizedTileInteraction() {
        @Override
        public void handleTile(Tile tile) {
          tile.addFood(energy / pieces, hue, true);
        }
      });
      softBodyLinAlgPool.recycle(tileLocation);
    }
  }

  public void reproduce(double size) {
    plannedReproductionValue = size;
  }

  protected void doReproduce(List<SoftBody> colliders, double babySize) {
    int highestGen = 0;
    if (babySize >= 0) {
      parentsList.clear();
      parentsList.add(this);
      double availableEnergy = getBabyEnergy();
      for (final SoftBody possibleParentBody : colliders) {
        if (Creature.class.isInstance(possibleParentBody)) {
          final Creature possibleParent = Creature.class.cast(possibleParentBody);
          if (possibleParent.brain.outputs()[9] > -1) { // Must be a WILLING creature to also give birth.
            final double distance = position.distance(possibleParent.getPosition());
            double combinedRadius = getRadius() * FIGHT_RANGE + possibleParent.getRadius();
            if (distance < combinedRadius) {
              parentsList.add(possibleParent);
              availableEnergy += possibleParent.getBabyEnergy();
            }
          }
        }
      }
      if (availableEnergy > babySize) {
        final Vector2D newPosition = softBodyLinAlgPool.getVector2D();
        final Vector2D newVelocity = softBodyLinAlgPool.getVector2D();
        double newHue = 0;
        double newSaturation = 0;
        double newBrightness = 0;
        double newMouthHue = 0;
        int parentsTotal = parentsList.size();
        String[] parentNames = new String[parentsTotal];
        Brain newBrain = brain.evolve(parentsList);
        for (int i = 0; i < parentsTotal; i++) {
          int chosenIndex = (int) random(0, parentsList.size());
          final Creature parent = parentsList.get(chosenIndex);
          parentsList.remove(chosenIndex);
          
          // Weird accumulation
          parent.energy -= babySize * (parent.getBabyEnergy() / availableEnergy);
          
          // Normal averaging/determining max value
          newPosition.inplaceAdd(parent.getPosition());
          newHue += parent.hue / parentsTotal;
          newSaturation += parent.saturation / parentsTotal;
          newBrightness += parent.brightness / parentsTotal;
          newMouthHue += parent.mouthHue / parentsTotal;
          parentNames[i] = parent.name;
          if (parent.gen > highestGen) {
            highestGen = parent.gen;
          }
        }
        newPosition.inplaceMul(1.0 / (double) parentsTotal);
        newSaturation = 1;
        newBrightness = 1;
        
        board.addCreature(new Creature(board.generateUniqueId(), newPosition, newVelocity, 
          babySize, density, newHue, newSaturation, newBrightness, board, board.getCurrentYear(), random(0, 2 * PI), 0, 
          stitchName(parentNames), andifyParents(parentNames), true, 
          newBrain, highestGen + 1, newMouthHue));
          
        softBodyLinAlgPool.recycle(newPosition);
        softBodyLinAlgPool.recycle(newVelocity);
      }
    }
  }

  public String stitchName(String[] s) {
    String result = "";
    for (int i = 0; i < s.length; i++) {
      float portion = ((float)s[i].length()) / s.length;
      int start = (int)min(max(round(portion * i), 0), s[i].length());
      int end = (int)min(max(round(portion * (i + 1)), 0), s[i].length());
      result = result + s[i].substring(start, end);
    }
    return result;
  }

  public String andifyParents(String[] s) {
    String result = "";
    for (int i = 0; i < s.length; i++) {
      if (i >= 1) {
        result = result + " & ";
      }
      result = result + capitalize(s[i]);
    }
    return result;
  }

  public String getCreatureName() {
    return capitalize(name);
  }

  public String capitalize(String n) {
    return n.substring(0, 1).toUpperCase() + n.substring(1, n.length());
  }

  public void applyMotions(double timeStep) {
    final Vector2D tileLocation = getRandomCoveredTileLocation();
    board.interactWithTileAtLocation(tileLocation, new SynchronizedTileInteraction() {
      @Override
      public void handleTile(Tile tile) {
        if (tile.fertility > 1) {
          loseEnergy(SWIM_ENERGY * energy);
        }
      }
    });
    softBodyLinAlgPool.recycle(tileLocation);
    
    super.applyMotions(timeStep);
    rotation += vr;
    vr *= Math.max(0, 1 - FRICTION / getMass());
  }

  public double getEnergyUsage(double timeStep) {
    return (energy - previousEnergy[ENERGY_HISTORY_LENGTH - 1]) / ENERGY_HISTORY_LENGTH / timeStep;
  }

  public double getBabyEnergy() {
    return energy - SAFE_SIZE;
  }

  public void addEnergy(double amount) {
    energy += amount;
  }

  public void setPreviousEnergy() {
    for (int i = ENERGY_HISTORY_LENGTH - 1; i >= 1; i--) {
      previousEnergy[i] = previousEnergy[i - 1];
    }
    previousEnergy[0] = energy;
  }

  public double measure(int choice) {
    int sign = 1 - 2 * (choice % 2);
    if (choice < 2) {
      return sign * energy;
    } else if (choice < 4) {
      return sign * birthTime;
    } else if (choice == 6 || choice == 7) {
      return sign * gen;
    }
    return 0;
  }



  public void setHue(double set) {
    hue = Math.min(Math.max(set, 0), 1);
  }

  public void setMouthHue(double set) {
    mouthHue = Math.min(Math.max(set, 0), 1);
  }

  public void setSaturarion(double set) {
    saturation = Math.min(Math.max(set, 0), 1);
  }

  public void setBrightness(double set) {
    brightness = Math.min(Math.max(set, 0), 1);
  }


  private Creature theClone = null;
  @Override
  public SoftBody getUpdatedStaticClone() {
   if (theClone == null) {
     theClone = new Creature(getId(), position, velocity, energy, density, hue, saturation, brightness, board, birthTime, 
                             rotation, vr, name, parents, false, brain, gen, mouthHue);
    } else {
      updateStaticCloneCreature(theClone);
    }
    return theClone;
  }
  
  protected void updateStaticCloneCreature(Creature theClone) {
    theClone.preferredRank = preferredRank;
    theClone.mouthHue = mouthHue;
    theClone.vr = vr;
    theClone.rotation = rotation;
    theClone.fightLevel = fightLevel;
    updateStaticCloneSoftBody(theClone);
 }
}