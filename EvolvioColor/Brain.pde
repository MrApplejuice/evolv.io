import java.util.Random;

public static final int MEMORY_COUNT = 12;
public static final int BRAIN_WIDTH = 4;
public static final int BRAIN_INPUT_COUNT = 11;
public static final int BRAIN_HEIGHT = BRAIN_INPUT_COUNT + MEMORY_COUNT + 1;

public static final long BRAIN_INTEGER_FACTOR = 100000;
public static final long BRAIN_INTEGER_CLIP_BOUND = 10000 * BRAIN_INTEGER_FACTOR;

public static final long STARTING_WEIGHT_VARIABILITY = (long) (10.0 * BRAIN_INTEGER_FACTOR);

public static final long LONG_SIGMOID_RANGE = 100 * BRAIN_INTEGER_FACTOR;
public static final int LONG_SIGMOID_RESOLUTION = 100000;
public static final long[] LONG_SIGMOID_LOOKUP = new long[LONG_SIGMOID_RESOLUTION + 1];

public static String[] BRAIN_INPUT_LABELS = new String[BRAIN_HEIGHT]; 
public static String[] BRAIN_OUTPUT_LABELS = new String[BRAIN_HEIGHT]; 

static {
  for (int i = 0; i <= LONG_SIGMOID_RESOLUTION; i++) {
    LONG_SIGMOID_LOOKUP[i] = (long) (((double) BRAIN_INTEGER_FACTOR) / (1.0d + Math.exp(-((double) LONG_SIGMOID_RANGE / (double) BRAIN_INTEGER_FACTOR * ((double) i / (double) LONG_SIGMOID_RESOLUTION)))));
  }
}

static {
  //initialize labels
  String[] baseInput = {
    "0Hue", "0Sat", "0Bri", "1Hue", "1Sat", 
    "1Bri", "2Hue", "2Sat", "2Bri", "Size", 
    "MHue"};
  String[] baseOutput = {
    "BHue", "Accel.", "Turn", "Eat", "Fight", 
    "Birth", "How funny?", "How popular?", "How generous?", "How smart?", 
    "MHue"};
  
  for (int i = 0; i < BRAIN_INPUT_COUNT; i++) {
    BRAIN_INPUT_LABELS[i + 1] = baseInput[i];
    BRAIN_OUTPUT_LABELS[i + 1] = baseOutput[i];
  }
  for (int i = 0; i < MEMORY_COUNT; i++) {
    BRAIN_INPUT_LABELS[i + 12]= "memory" + (i + 1);
    BRAIN_OUTPUT_LABELS[i + 12] = "memory" + (i + 1);
  }
  BRAIN_INPUT_LABELS[0] = "const.";
  BRAIN_OUTPUT_LABELS[0] = "const.";
}

/**
  For optimization purposes, the "new brain" uses integer algebra to do the neural
  network computations.
 */
public class Brain {
  private Random random = new Random();

  private long[][][] weights;   // Indexing: [neuron-layer][neuron-index][neuron-input-index]
  private long[][] activations; // Indexing: [neuron-layer][neuron-index]

  public Brain(final long[][][] tweights, final long[][] tactivations) {
    //initialize brain
    weights = new long[BRAIN_WIDTH - 1][BRAIN_HEIGHT][BRAIN_HEIGHT];
    for (int layer = 0; layer < BRAIN_WIDTH - 1; layer++) {
      for (int i = 0; i < BRAIN_HEIGHT; i++) {
        for (int ci = 0; ci < BRAIN_HEIGHT; ci++) {
          if (tweights != null) {
            weights[layer][i][ci] = tweights[layer][i][ci];
          } else {
            weights[layer][i][ci] = random.nextLong() % (2 * STARTING_WEIGHT_VARIABILITY + 1) - STARTING_WEIGHT_VARIABILITY;
          }
        }
      }
    }
    
    activations = new long[BRAIN_WIDTH][BRAIN_HEIGHT];
    for (int layer = 0; layer < BRAIN_WIDTH; layer++) {
      for (int i = 0; i < BRAIN_HEIGHT; i++) {
        if (tactivations != null) {
          activations[layer][i] = tactivations[layer][i];
        } else {
          activations[layer][i] = i == 0 ? 1 * BRAIN_INTEGER_FACTOR : 0;
        }
      }
    }
  }

  public Brain evolve(List<Creature> parents) {
    // Initialize new weights
    long[][][] newWeightAbsWeightSum = new long[BRAIN_WIDTH - 1][BRAIN_HEIGHT][BRAIN_HEIGHT];
    long[][][] newWeightWeightedSums = new long[BRAIN_WIDTH - 1][BRAIN_HEIGHT][BRAIN_HEIGHT];
    
    for (int layer = 0; layer < BRAIN_WIDTH - 2; layer++) {
      for (int i = 0; i < BRAIN_HEIGHT; i++) {
        for (int ci = 0; ci < BRAIN_HEIGHT; ci++) {
          newWeightAbsWeightSum[layer][i][ci] = 0;
          newWeightWeightedSums[layer][i][ci] = 0;
        }
      }
    }
    
    // Create weighted end-point cross over function. The goal here is to only 
    // start from an output neuron and trace its inputs back to the inputs. And use
    // the weights along this trail to modify the weights for each parent.  
    long[] tracedWeights = new long[BRAIN_HEIGHT];
    long[] newTracedWeights = new long[BRAIN_HEIGHT];
    
    for (int outNodeIndex = 0; outNodeIndex < BRAIN_HEIGHT; outNodeIndex++) {
      final int selectedParent = random.nextInt(parents.size());
      final Brain parentBrain = parents.get(selectedParent).getBrain();
      
      for (int ci = 0; ci < BRAIN_HEIGHT; ci++) {
        final long w = parentBrain.weights[BRAIN_WIDTH - 2][outNodeIndex][ci];
        tracedWeights[ci] = w;
        newWeightAbsWeightSum[BRAIN_WIDTH - 2][outNodeIndex][ci] = 1;
        newWeightWeightedSums[BRAIN_WIDTH - 2][outNodeIndex][ci] = w;
      }
      
      for (int layer = BRAIN_WIDTH - 3; layer >= 0; layer--) {
        for (int ci = 0; ci < BRAIN_HEIGHT; ci++) {
          newTracedWeights[ci] = 0;
        }
        
        for (int i = 0; i < BRAIN_HEIGHT; i++) {
          for (int ci = 0; ci < BRAIN_HEIGHT; ci++) {
            final long w = parentBrain.weights[layer][i][ci];
            newTracedWeights[ci] += tracedWeights[i] * w / BRAIN_INTEGER_FACTOR;
            newWeightAbsWeightSum[layer][i][ci] += Math.abs(w);
            newWeightWeightedSums[layer][i][ci] += Math.abs(w) * w;
          }
        }
        
        for (int ci = 0; ci < BRAIN_HEIGHT; ci++) {
          tracedWeights[ci] = newTracedWeights[ci] / BRAIN_HEIGHT;
        }
      }
    }
    
    // Calculate the weights - apply mutation if applicable
    final long MUTATION_RATE = (long) (0.1 * BRAIN_INTEGER_FACTOR);
    
    for (int layer = 0; layer < BRAIN_WIDTH - 1; layer++) {
      for (int i = 0; i < BRAIN_HEIGHT; i++) {
        for (int ci = 0; ci < BRAIN_HEIGHT; ci++) {
          if (newWeightAbsWeightSum[layer][i][ci] == 0) {
            newWeightWeightedSums[layer][i][ci] = 0;
          } else {
            newWeightWeightedSums[layer][i][ci] = newWeightWeightedSums[layer][i][ci] / newWeightAbsWeightSum[layer][i][ci];
          }
          
          // Do an incremental mutation like in the earlier implementation
          if ((random.nextLong() % BRAIN_INTEGER_FACTOR) < MUTATION_RATE) {
            long offset = random.nextLong() % BRAIN_INTEGER_FACTOR;
            newWeightWeightedSums[layer][i][ci] += offset * offset / BRAIN_INTEGER_FACTOR;
          }
        }
      }
    }
    
    return new Brain(newWeightWeightedSums, null);
  }

  public void draw(PFont font, float scaleUp, int mX, int mY) {
    final float neuronSize = 0.4;
    noStroke();
    fill(0, 0, 0.4);
    rect((-1.7 - neuronSize) * scaleUp, -neuronSize * scaleUp, (2.4 + BRAIN_WIDTH + neuronSize * 2) * scaleUp, (BRAIN_HEIGHT + neuronSize * 2) * scaleUp);

    ellipseMode(RADIUS);
    strokeWeight(2);
    textFont(font, 0.58 * scaleUp);
    fill(0, 0, 1);
    for (int y = 0; y < BRAIN_HEIGHT; y++) {
      String text;

      if (y < BRAIN_INPUT_LABELS.length) {
        text = BRAIN_INPUT_LABELS[y];
      } else {
        text = "Unk. " + y;
      }
      textAlign(RIGHT);
      text(text, (-neuronSize - 0.1) * scaleUp, (y + (neuronSize * 0.6)) * scaleUp);

      if (y < BRAIN_OUTPUT_LABELS.length) {
        text = BRAIN_OUTPUT_LABELS[y];
      } else {
        text = "Unk. " + y;
      }
      textAlign(LEFT);
      text(text, (BRAIN_WIDTH - 1 + neuronSize + 0.1) * scaleUp, (y + (neuronSize * 0.6)) * scaleUp);
    }
    textAlign(CENTER);
    for (int x = 0; x < BRAIN_WIDTH; x++) {
      for (int y = 0; y < BRAIN_HEIGHT; y++) {
        noStroke();
        double val = (double) activations[x][y] / (double) BRAIN_INTEGER_FACTOR;
        fill(neuronFillColor(val));
        ellipse(x * scaleUp, y * scaleUp, neuronSize * scaleUp, neuronSize * scaleUp);
        fill(neuronTextColor(val));
        text(nf((float)val, 0, 1), x * scaleUp, (y + (neuronSize * 0.6)) * scaleUp);
      }
    }
    if (mX >= 0 && mX < BRAIN_WIDTH && mY >= 0 && mY < BRAIN_HEIGHT) {
      for (int y = 0; y < BRAIN_HEIGHT; y++) {
        if (mX >= 1 && mY < BRAIN_HEIGHT - 1) {
          drawAxon(mX - 1, y, mX, mY, scaleUp);
        }
        if (mX < BRAIN_WIDTH - 1 && y < BRAIN_HEIGHT - 1) {
          drawAxon(mX, mY, mX + 1, y, scaleUp);
        }
      }
    }
  }

  public void propagateInputs(double[] inputs) {
    for (int i = 0; i < BRAIN_INPUT_COUNT; i++) {
      if (i < inputs.length) {
        activations[0][i + 1] = (long) (inputs[i] * BRAIN_INTEGER_FACTOR);
      } else {
        activations[0][i + 1] = 0;
      }
    }
    for (int i = 1 + BRAIN_INPUT_COUNT; i < BRAIN_WIDTH; i++) {
      activations[0][i] = activations[BRAIN_WIDTH - 1][i];
    }
    
    
    for (int layer = 0; layer < BRAIN_WIDTH - 1; layer++) {
      for (int i = 1; i < BRAIN_HEIGHT; i++) {
        activations[layer + 1][i] = 0;
      }
      
      for (int i = 1; i < BRAIN_HEIGHT; i++) {
        for (int ci = 0; ci < BRAIN_HEIGHT; ci++) {
          activations[layer + 1][i] += weights[layer][i][ci] * activations[layer][ci] / BRAIN_INTEGER_FACTOR;
        }
      }
      
      // Do not apply a sigmoid to the final layer!
      if (layer < BRAIN_WIDTH - 2) {
        for (int i = 1; i < BRAIN_HEIGHT; i++) {
          activations[layer + 1][i] = sigmoid(activations[layer + 1][i]);
        }
      }
    }
  }

  public double getOutput(int i) {
    i--;
    if ((i >= 0) && (i < BRAIN_INPUT_COUNT)) {
      return (double) (activations[BRAIN_WIDTH - 1][i + 1]) / (double) BRAIN_INTEGER_FACTOR;
    }
    return 0;
  }


  private void drawAxon(int x1, int y1, int x2, int y2, float scaleUp) {
    stroke(neuronFillColor((double) weights[x1][y2][y1] / (double) BRAIN_INTEGER_FACTOR));

    line(x1 * scaleUp, y1 * scaleUp, x2 * scaleUp, y2 * scaleUp);
  }

  private long sigmoid(long input) {
    if (input < 0) {
      return BRAIN_INTEGER_FACTOR - sigmoid(-input); 
    } else if (input >= LONG_SIGMOID_RANGE) {
      return LONG_SIGMOID_LOOKUP[LONG_SIGMOID_RESOLUTION];
    } else {
      return LONG_SIGMOID_LOOKUP[(int) (input * (LONG_SIGMOID_RESOLUTION + 1) / LONG_SIGMOID_RANGE)];
    }
  }

  private color neuronFillColor(double d) {
    if (d >= 0) {
      return color(0, 0, 1, (float)(d));
    } else {
      return color(0, 0, 0, (float)(-d));
    }
  }

  private color neuronTextColor(double d) {
    if (d >= 0) {
      return color(0, 0, 0);
    } else {
      return color(0, 0, 1);
    }
  }
}