import 'dart:async';
import 'dart:core';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:http/http.dart' as http;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Air Quality',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(title: 'Air Quality'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class StreamData {
  final DateTime dataTime;
  final double dataValue;
  StreamData(this.dataTime, this.dataValue);
}

class _MyHomePageState extends State<MyHomePage> {
  // final _formKey = GlobalKey<FormState>();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _statementsUpload = false;

  //initial data
  String _dateNow;
  String _timeNow;
  String _valueCO;

  String broker = 'broker.hivemq.com';
  int port = 1883;
  String clientIdentifier = 'kws';

  mqtt.MqttClient client;
  mqtt.MqttConnectionState connectionState;

  DateTime _clockTime;
  double _carbonMonoxideValue = 0;
  var _streamData = [
    StreamData(
        DateFormat("hh:mm:ss")
            .parse(DateFormat('Hms').format(DateTime.now()).toString()),
        0),
  ];

  StreamSubscription subscription;

  void _subscribeToTopic(String topic) {
    if (connectionState == mqtt.MqttConnectionState.connected) {
      print('[MQTT client] Subscribing to ${topic.trim()}');
      client.subscribe(topic, mqtt.MqttQos.exactlyOnce);
    }
  }

  void _showSnackbar(String message) {
    final snackBar = SnackBar(content: Text(message));
    _scaffoldKey.currentState.showSnackBar(snackBar);
  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;

    final double itemHeight = (size.height - kToolbarHeight - 480) / 2;
    final double itemWidth = size.width / 2;

    var seriesChart = [
      charts.Series<StreamData, DateTime>(
          domainFn: (StreamData stream, _) => stream.dataTime,
          measureFn: (StreamData stream, _) => stream.dataValue,
          id: "value",
          data: _streamData),
    ];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey[700],
      appBar: AppBar(
        backgroundColor: Colors.orange[800],
        leading: Image.asset(
          "assets/icons/icon_weather.png",
          scale: 6,
        ),
        title: Center(
          child: Text("Air Quality",
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              )),
        ),
        actions: <Widget>[
          Container(
            margin: const EdgeInsets.only(right: 5.0),
            width: 43,
            child: FloatingActionButton(
              backgroundColor: Colors.orange,
              onPressed: _connect,
              child: Icon(
                Icons.play_circle_outline,
                color: Colors.white,
                size: 37.0,
              ),
            ),
          ),
        ],
      ),
      body: GridView.count(
        crossAxisCount: 1,
        childAspectRatio: (itemWidth / itemHeight),
        children: <Widget>[
          CardSensor(
            iconVar: "assets/icons/icon_co.png",
            textVar: "Data Sensor : Carbon Monoxide (CO)",
            valuVar: "$_carbonMonoxideValue",
            unitVar: "ppm",
          ),
          Container(
            child: Card(
              shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: Colors.orange,
                    width: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(10)),
              color: Colors.white,
              margin: EdgeInsets.all(10),
              child: charts.TimeSeriesChart(
                seriesChart,
                animate: false,
                defaultRenderer: new charts.LineRendererConfig(
                    includePoints: true, includeArea: true),
              ),
            ),
          ),
          CardGauge(
            values: _carbonMonoxideValue.toDouble(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: uploadTrue,
        tooltip: 'save',
        backgroundColor: Colors.white,
        child: Icon(Icons.cloud_upload, color: Colors.orange, size: 37.0),
      ),
    );
  }

  void _connect() async {
    client = mqtt.MqttClient(broker, '');
    client.port = port;
    client.logging(on: true);
    client.keepAlivePeriod = 30;
    client.onDisconnected = _onDisconnected;

    final mqtt.MqttConnectMessage connMess = mqtt.MqttConnectMessage()
        .withClientIdentifier(clientIdentifier)
        .startClean() // Non persistent session for testing
        .keepAliveFor(30)
        .withWillQos(mqtt.MqttQos.atMostOnce);
    print('[MQTT client] MQTT client connecting....');
    client.connectionMessage = connMess;

    try {
      _showSnackbar('connecting to mqtt...');
      await client.connect();
      _showSnackbar('mqtt connected');
    } catch (e) {
      print(e);
      _showSnackbar('failed connect to mqtt!!!');
      _disconnect();
    }

    /// Check if we are connected
    // ignore: deprecated_member_use
    if (client.connectionState == mqtt.MqttConnectionState.connected) {
      print('[MQTT client] connected');
      setState(() {
        // ignore: deprecated_member_use
        connectionState = client.connectionState;
      });
    } else {
      _showSnackbar('mqtt disconnected');
      print('[MQTT client] ERROR: MQTT client connection failed - '
          // ignore: deprecated_member_use
          'disconnecting, state is ${client.connectionState}');
      _disconnect();
    }
    subscription = client.updates.listen(_onMessage);

    _subscribeToTopic("airquality/data/co");
  }

  void _disconnect() {
    print('[MQTT client] _disconnect()');
    client.disconnect();
    _onDisconnected();
  }

  void _onDisconnected() {
    print('[MQTT client] _onDisconnected');
    setState(() {
      // ignore: deprecated_member_use
      connectionState = client.connectionState;
      client = null;
      subscription.cancel();
      subscription = null;
    });
    print('[MQTT client] MQTT client disconnected');
  }

  void _onMessage(List<mqtt.MqttReceivedMessage> event) {
    final mqtt.MqttPublishMessage recMess =
        event[0].payload as mqtt.MqttPublishMessage;
    final String message =
        mqtt.MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
    print("${event.length} | ${event[0].topic} : $message");
    if (event.length >= 1) {
      var receiveData = parsingRawData(message, ",");
      setState(() {
        _carbonMonoxideValue = double.parse(receiveData[0]);

        _dateNow = DateFormat('yMd').format(DateTime.now()).toString();
        _timeNow = DateFormat('Hms').format(DateTime.now()).toString();
        _valueCO = _carbonMonoxideValue.toString();

        _clockTime = DateFormat("hh:mm:ss")
            .parse(DateFormat('Hms').format(DateTime.now()).toString());
        if (_streamData.length > 15) {
          _streamData.removeAt(0);
        } else {
          _streamData.add(StreamData(_clockTime, _carbonMonoxideValue));
        }
      });

      if (_statementsUpload == true) {
        postRequest();
      }
    } else {
      _showSnackbar("No data received, check your device!");
    }
  }

  void uploadTrue() {
    _statementsUpload = true;
    _showSnackbar("sending data to spreadsheet!");
  }

  //save data to google spreadsheets
  postRequest() async {
    Map data = {'dateNow': _dateNow, 'timeNow': _timeNow, 'valueCO': _valueCO};
    var url =
        'https://script.google.com/macros/s/AKfycbyku4B-9mwIdxPRMJzdUoIhkq_nOb23rQwD1hgzZaBEkuZXPhI/exec';
    http.post(url, body: data).then((response) {
      print("Response status: ${response.statusCode}");
      print("Response body: ${response.body}");
    });
  }
}

class CardSensor extends StatelessWidget {
  CardSensor({this.iconVar, this.textVar, this.valuVar, this.unitVar});
  final String iconVar;
  final String textVar;
  final String valuVar;
  final String unitVar;

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Card(
        color: Colors.orange,
        margin: EdgeInsets.all(10),
        child: Column(
          children: <Widget>[
            ListTile(
              leading: Image.asset(
                iconVar,
              ),
              title: Text(textVar,
                  style: TextStyle(
                    fontSize: 17,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  )),
            ),
            Text(valuVar,
                style: TextStyle(
                  fontSize: 85,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                )),
            Text(unitVar,
                style: TextStyle(
                  fontSize: 25,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                )),
          ],
        ),
      ),
    );
  }
}

class CardGauge extends StatelessWidget {
  CardGauge({this.values});
  final double values;

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Card(
        color: Colors.orange[300],
        margin: EdgeInsets.all(10),
        child: SfRadialGauge(
            title: GaugeTitle(
                text: 'Batas Level Karbon Monoksida',
                textStyle: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontStyle: FontStyle.normal,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Roboto')),
            axes: <RadialAxis>[
              RadialAxis(minimum: 0, maximum: 200, ranges: <GaugeRange>[
                GaugeRange(startValue: 0, endValue: 50, color: Colors.green),
                GaugeRange(startValue: 50, endValue: 100, color: Colors.yellow),
                GaugeRange(
                    startValue: 100, endValue: 150, color: Colors.orange),
                GaugeRange(startValue: 150, endValue: 200, color: Colors.red)
              ], pointers: <GaugePointer>[
                NeedlePointer(value: values, needleColor: Colors.white)
              ]),
            ]),
      ),
    );
  }
}

List parsingRawData(data, delimiter) {
  var resultData = new List(1);
  resultData = data.toString().split(delimiter);
  return resultData;
}
