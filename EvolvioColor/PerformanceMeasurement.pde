import java.lang.reflect.InvocationTargetException;

import java.util.List;
import java.util.Map;
import java.util.HashMap;

import java.awt.Dimension;
import java.awt.GridLayout;

import javax.swing.JFrame;
import javax.swing.SwingUtilities;

import org.jfree.chart.JFreeChart;
import org.jfree.chart.ChartPanel;
import org.jfree.chart.axis.NumberAxis;
import org.jfree.chart.plot.XYPlot;
import org.jfree.data.xy.AbstractXYDataset;
import org.jfree.chart.renderer.xy.XYSplineRenderer;

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
    double time = (System.nanoTime() - startTime) / 1000000.0d;
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
  
  public void logMetric(double ms) {
    int i;
    synchronized (this) {
      i = rotatingLoggerIndex++;
      if (rotatingLoggerIndex >= ROTATING_LOGGER_COUNT) {
        rotatingLoggerIndex = 0;
      }
    }
    
    synchronized (loggers[i]) {
      loggers[i].add(new Double(ms));
    }
  }
  
  /**
    Obtains the averaged recorded values and removes all recorded data.
   */
  public synchronized double cycleData() {
    return calculateAveragedDataAndPurge(0, 0.0d, 0);
  }
  
  private synchronized double calculateAveragedDataAndPurge(int i, double runningSum, int count) {
    if (i >= ROTATING_LOGGER_COUNT) {
      if (count == 0) {
        return 0;
      }
      return runningSum / count;
    } else {
      synchronized (loggers[i]) {
        for (final Object o : loggers[i]) {
          runningSum += (Double) o;
        }
        count += loggers[i].size();
        loggers[i].clear();
      }
      return calculateAveragedDataAndPurge(i + 1, runningSum, count);
    }
  }
}

/**
  A class that supplies an ugly interface for visualizing performance data.
  Uses JFreeChart to do so. The class tries to load the library dynamically,
  and if unsuccesful, fails silently.
 */
public static class PerformanceMeasurer {
  public static final int MAX_SAMPLE_COUNT = 200;
  
  private static class GroupChart {
    private XYDataset xydataset = new AbstractXYDataset() {
      @Override
      public int getSeriesCount() {
        return metricNames.size();
      }
      
      @Override
      public Comparable getSeriesKey(int series) {
        return metricNames.get(series);
      }
      
      @Override
      public int getItemCount(int series) {
        int itemCount = 0;
        for (Double i : values.get(series)) {
          if (i != null) {
            itemCount++;
          }
        }
        return itemCount;
      }
      
      @Override
      public Number getX(int series, int item) {
        int xindex = 0;
        for (Double i : values.get(series)) {
          xindex++;
          if (i != null) {
            if (item == 0) {
              return xindex;
            }
            item--;
          }
        }
        return null;
      }
      
      @Override
      public Number getY(int series, int item) {
        for (Double i : values.get(series)) {
          if (i != null) {
            if (item == 0) {
              return i;
            }
            item--;
          }
        }
        return null;
      }
    };
    
    private XYPlot plot;
    private NumberAxis xAxis, yAxis;
    private ChartPanel chart;
    
    private int maxCycle = 0;
    private double maxValue = 0;
    
    private List<String> metricNames = new ArrayList<String>();
    private List<List<Double>> values = new ArrayList<List<Double>>();
    
    public GroupChart(String groupTitle) {
      xAxis = new NumberAxis("draw cycle");
      yAxis = new NumberAxis("ms");
      
      plot = new XYPlot(xydataset, xAxis, yAxis, new XYSplineRenderer());
      
      chart = new ChartPanel(new JFreeChart(groupTitle, plot));
    }
    
    public ChartPanel getChart() {
      return chart;
    }
    
    public void log(String metricName, int xindex, double ms) {
      maxCycle = Math.max(maxCycle, xindex);
      maxValue = Math.max(maxValue, ms);
      
      List<Double> metricValues = null; 
      if (!metricNames.contains(metricName)) {
        metricNames.add(metricName);
        metricValues = new ArrayList<Double>();
        values.add(metricValues);
      } else {
        metricValues = values.get(metricNames.indexOf(metricName));
      }
      
      while (xindex >= metricValues.size()) {
        metricValues.add(null);
      }
      
      metricValues.set(xindex, ms);
    }
    
    public void update() {
      xAxis.setRange(0, maxCycle);
      yAxis.setRange(0, Math.pow(2, Math.ceil(Math.log(maxValue) / Math.log(2.0d))));
      chart.getChart().fireChartChanged();
      chart.invalidate();
    }
  }
  
  private JFrame window = null;

  private int cycleCounter = 0;
  private Map<String, Map<String, AverageLogger>> loggerMap = new HashMap<String, Map<String, AverageLogger>>();
  
  private class GroupChartNameRecord {
    public String name;
    public GroupChart chart;
    
    public GroupChartNameRecord(String name, GroupChart chart) {
      this.name = name;
      this.chart = chart;
    }
  };
  private List<GroupChartNameRecord> groupChartList = new ArrayList<GroupChartNameRecord>();
  
  {
    try {
      SwingUtilities.invokeAndWait(new Runnable() {
        @Override
        public void run() {
          window = new JFrame("Performance logger");
          window.setDefaultCloseOperation(JFrame.HIDE_ON_CLOSE);
          window.setMinimumSize(new Dimension(400, 300));

          GridLayout layout = new GridLayout(0, 3);
          window.setLayout(layout);
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
    Retrieves the GroupChart for the given groupName. If the GroupChart
    does not exist yet, it will be created.
   */
  private GroupChart getGroupChartForGroup(final String groupName) {
    for (GroupChartNameRecord gcnr : groupChartList) {
      if (gcnr.name.equals(groupName)) {
        return gcnr.chart;
      }
    }
    
    final GroupChartNameRecord gcnr = new GroupChartNameRecord(groupName, null);
    try {
      SwingUtilities.invokeAndWait(new Runnable() {
        @Override
        public void run() {
          final GroupChart gc = new GroupChart(groupName);
          gcnr.chart = gc;
          
          window.getContentPane().add(gc.getChart());
        }
      });
    }
    catch (InvocationTargetException e) {
      e.printStackTrace();
      return null;
    }
    catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return null;
    }
    groupChartList.add(gcnr);
    
    return gcnr.chart;
  }
  
  /**
    Cycle the averaged logger data and update the display.
   */
  public synchronized void cycle() {
    cycleCounter++;
    
    for (final Map.Entry<String, Map<String, AverageLogger>> groupNameMetricMapEntry : loggerMap.entrySet()) {
      try {
        final GroupChart gchart = getGroupChartForGroup(groupNameMetricMapEntry.getKey());
        SwingUtilities.invokeAndWait(new Runnable() {
          @Override
          public void run() {
            for (final Map.Entry<String, AverageLogger> metricLoggerEntry : groupNameMetricMapEntry.getValue().entrySet()) {
              double timeValue = metricLoggerEntry.getValue().cycleData();
              gchart.log(metricLoggerEntry.getKey(), cycleCounter, timeValue);
            }
            gchart.update();
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
  }
  
  /**
    Returns a logger for the given group and metric.
   */
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