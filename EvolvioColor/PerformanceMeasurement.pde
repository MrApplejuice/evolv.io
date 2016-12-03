import java.lang.reflect.InvocationTargetException;

import java.util.List;
import java.util.Map;
import java.util.HashMap;

import java.awt.Dimension;

import javax.swing.JFrame;
import javax.swing.SwingUtilities;

import org.jfree.chart.JFreeChart;

/**
   Helper to generate timing information for a AverageLogger. Not
   thread safe!
 */
public static class LoggerStopWatch {
  private AverageLogger logger;
  private long startTime = System.nanoTime(); 
  
  public LoggerStopWatch(AverageLogger logger) {
    this.logger = logger;
  }
  
  public void start() {
    startTime = System.nanoTime();
  }
  
  public void lap() {
    int time = (int) (System.nanoTime() - startTime);
    logger.logMetric(time);
  }
}

/**
  Utility class that is used by the perforamce measurer to do
  efficient and thread safe measurements of metrics.
 */
public static class AverageLogger {
  private static final int ROTATING_LOGGER_COUNT = 16;
  
  private int rotatingLoggerIndex = 0;
  private List[] loggers = new List[ROTATING_LOGGER_COUNT];
  
  {
    for (int i = 0; i < loggers.length; i++) {
      loggers[i] = new ArrayList();
    }
  }
  
  public void logMetric(int number) {
    int i;
    synchronized (this) {
      i = rotatingLoggerIndex++;
      if (rotatingLoggerIndex >= ROTATING_LOGGER_COUNT) {
        rotatingLoggerIndex = 0;
      }
    }
    
    synchronized (loggers[i]) {
      loggers[i].add(new Integer(number));
    }
  }
  
  /**
    Obtains the averaged recorded values and removes all recorded data.
   */
  public synchronized int cycleData() {
    return calculateAveragedDataAndPurge(0, 0, 0);
  }
  
  private synchronized int calculateAveragedDataAndPurge(int i, long runningSum, int count) {
    if (i >= ROTATING_LOGGER_COUNT) {
      if (count == 0) {
        return 0;
      }
      return (int) (runningSum / count);
    } else {
      synchronized (loggers[i]) {
        for (final Object o : loggers[i]) {
          runningSum += (Integer) o;
        }
        count += loggers[i].size();
        loggers[i].clear();
      }
      return calculateAveragedDataAndPurge(i++, runningSum, count);
    }
  }
}

/**
  A class that supplies an ugly interface for visualizing performance data.
  Uses JFreeChart to do so. The class tries to load the library dynamically,
  and if unsuccesful, fails silently.
 */
public static class PerformanceMeasurer {
  private JFrame window = null;
  
  private Map<String, Map<String, AverageLogger>> loggerMap = new HashMap<String, Map<String, AverageLogger>>();
  
  {
    try {
      SwingUtilities.invokeAndWait(new Runnable() {
        @Override
        public void run() {
          window = new JFrame("Performance logger");
          window.setDefaultCloseOperation(JFrame.HIDE_ON_CLOSE);
          window.setMinimumSize(new Dimension(400, 300));
        }
      });
    }
    catch (InvocationTargetException e) {
      e.printStackTrace();
    }
    catch (InterruptedException e) {
      Thread.currentThread().interrupt();
    }
  }
  
  /**
    Shows the performance measurement window and displays
    the measured data.
   */
  public void show() {
    SwingUtilities.invokeLater(new Runnable() {
      @Override
      public void run() {
        window.setVisible(true);
      }
    });
  }
  
  /**
    Cycle the averaged logger data and update the display.
   */
  public synchronized void cycle() {
    for (Map<String, AverageLogger> merticMap : loggerMap.values()) {
      for (AverageLogger logger : merticMap.values()) {
        logger.cycleData();
      }
    }
  }
  
  public synchronized AverageLogger getLogger(String groupName, String metricName) {
    Map<String, AverageLogger> metricMap = loggerMap.get(groupName);
    if (metricMap == null) {
      metricMap = new HashMap<String, AverageLogger>();
      loggerMap.put(groupName, metricMap);
    }
    
    AverageLogger metricLogger = metricMap.get(metricName);
    if (metricLogger == null) {
      metricLogger = new AverageLogger();
      metricMap.put(metricName, metricLogger);
    }
    
    return metricLogger;
  }
}