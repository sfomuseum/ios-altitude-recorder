import UIKit
import CoreLocation
import GeoJSON
import AnyCodable
import MapKit
import SwiftData

// https://medium.com/@ilya.virnik/tutorial-get-users-altitude-in-swift-33d23b299bbe
// https://developer.apple.com/documentation/corelocation/cllocation/1423820-altitude
// https://github.com/kiliankoe/GeoJSON/tree/main
// https://jokerpt.medium.com/using-swift-data-for-data-persistence-in-ios-17-uikit-13da38c8d779
// https://www.swiftbysundell.com/articles/property-observers-in-swift/
// https://developer.apple.com/documentation/corelocation/handling_location_updates_in_the_background

@Model
class LocationModel{
    @Attribute(.unique) var id: String
    var latitude: Double
    var longitude: Double
    var altitude: Double

    var time: Double
    
    init(id: String, latitude: Double, longitude: Double, altitude: Double,time: Double) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.time = time
    }
}

class ViewController: UIViewController {
        
    @IBOutlet var navbarTop: UINavigationItem!
    @IBOutlet var navbarBottom: UINavigationItem!
    
    @IBOutlet var barButtonItem: UIBarButtonItem!
    @IBOutlet var recordButton: UIButton!
    @IBOutlet var exportButton: UIButton!
    
    @IBOutlet var resetButton: UIButton!
    @IBOutlet var captureButton: UIButton!
    @IBOutlet var altitudeLabel: UILabel!
    @IBOutlet var countLocationsLabel: UILabel!
    
    @IBOutlet var mapView: MKMapView!
   
    private let locationManager = CLLocationManager()
    private var annotations = [MKPointAnnotation]()

    private var last_lat: Double?
    private var last_lon: Double?
    
    private var recording = false{
        willSet(v){
            switch(v){
            case true:
                exportButton.isEnabled = false
                captureButton.isEnabled = false
                recordButton.setTitle("Stop", for: .normal)
            default:
                captureButton.isEnabled = true
                recordButton.setTitle("Record", for: .normal)
                
                if captured > 0 {
                    resetButton.isEnabled = true
                    exportButton.isEnabled = true
                }
            }
        }
    }
    
    private var captured = 0{
        willSet(i) {
            
            switch (i) {
            case 0:
                self.countLocationsLabel.text = ""
                resetButton.isEnabled = false
                exportButton.isEnabled = false
                break
            default:
             
                self.countLocationsLabel.text = String(format: "%d Locations captured", i)
                
                if !recording {
                    exportButton.isEnabled = true
                    resetButton.isEnabled = true
                }
            }
        }
    }
    
    private var current_location: CLLocation?{
        willSet(loc){
            if !recording{
                captureButton.isEnabled = true
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Maybe make this an option but that would require
        // creating a "Settings" panel which feels like ya-shaving right now...
        // locationManager.requestWhenInUseAuthorization()
        
        locationManager.requestAlwaysAuthorization()
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
        locationManager.delegate = self
        
        captureButton.isEnabled = false
        exportButton.isEnabled = false
        resetButton.isEnabled = false
        
        navbarTop.title = "Altitude Recorder"
        self.countLocationsLabel.text = ""
        
        captured = countLocations()
    }
    
    @IBAction
    func resetLocations(){
        self.clearLocations()
        self.clearAnnotations()
        captured = 0
    }
    
    @IBAction
    func captureLocation(){
     
        if current_location == nil {
            return
        }
        
        self.saveLocation(location: current_location!)
        self.captured += 1
    }
    
    @IBAction
    func recordingOnclick() {
        
        if (recording){
            recording = false
        } else {
            recording = true
        }
        
    }
    
    @IBAction
    func exportLocations() {
        
        let featurecollection = asFeatureCollection()
        let json: Data?
        
        do {
            json = try JSONEncoder().encode(featurecollection)
        } catch  {
            print("SAD") // To do: Display alert
            return
        }
        
        shareGeoJSON(geojson: json!)
    }
    
    private func asFeatureCollection() -> FeatureCollection {
        
        var features = [Feature]()
        
        DatabaseService.shared.fetchLocations { data , error  in
            
            if let error{
                print(error)
            }
            if let data {
                
                for row in data {
                    
                    let pt = Point(longitude: row.longitude, latitude: row.latitude, altitude: row.altitude)
                                        
                    let f = Feature(
                        geometry: .point(pt),
                        properties: [
                            "timestamp": AnyCodable(Int(row.time)),
                            "altitude": AnyCodable(row.altitude),
                        ]
                    )
                    
                    features.append(f)
                }
            }
        }
        
        let featurecollection = FeatureCollection(features: features)
        return featurecollection
    }
    
    private func shareGeoJSON(geojson: Data) {
                
        // Write GeoJSON data to a temporary file so we can share it with a suitable
        // filename and extension.
        
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(),
                                            isDirectory: true)

        let ts = Int(Date().timeIntervalSince1970)
        let temporaryFilename = "altitude-recorder-\(ts).geojson"
        
        let temporaryFileURL =
            temporaryDirectoryURL.appendingPathComponent(temporaryFilename)
        
        do {
            try geojson.write(to: temporaryFileURL,
                              options: .atomic)

        } catch {
            print("SAD") // To do: Display alert
            return
        }
        
        let items = [temporaryFileURL]
        
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            ac.popoverPresentationController?.barButtonItem = barButtonItem
        }
        
        self.present(ac, animated: true)
    }
    
    private func clearAnnotations(){
        mapView.removeAnnotations(annotations)
        annotations = [MKPointAnnotation]()
    }
    
    private func saveLocation(location: CLLocation){
        DatabaseService.shared.saveLocation(location: location)
    }
    
    private func clearLocations(){
                
        DatabaseService.shared.fetchLocations { data , error  in
            
            if let error{
                print(error)
            }
            if let data {
                
                for row in data {
                    DatabaseService.shared.deleteLocation(Location: row)
                }
            }
        }
        
        captured = 0
    }
    
    private func countLocations() -> Int{
        var count = 0
        
        DatabaseService.shared.fetchLocations { data , error  in
            
            if let error{
                print(error)
            }
            if let data {
                
                for _ in data {
                    count += 1
                }
            }
        }
        
        return count
    }
}

extension ViewController: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        if let lastLocation = locations.last {
            
            let coords = lastLocation.coordinate
            let altitude = lastLocation.altitude
            
            let lat = coords.latitude
            let lon = coords.longitude
            
            altitudeLabel.text = String(format: "Altitude at %.6f, %.6f is: %.1f m (%.1f ft)", lat, lon, altitude, altitude * 3.2808 )
            
            if self.recording {
                
                var capture = true
                
                if self.captured > 1 {
                    
                    if last_lat == lat && last_lon == lon {
                        capture = false
                    }
                }
                
                if capture {
                    
                    self.saveLocation(location: lastLocation)
                    self.captured += 1
                }
                
            } else {
                
                self.clearAnnotations()
            }
            
            mapView.setCenter(coords, animated: true)
            
            let region = MKCoordinateRegion( center: coords, latitudinalMeters: CLLocationDistance(exactly: 100)!, longitudinalMeters: CLLocationDistance(exactly: 100)!)
            
            mapView.setRegion(mapView.regionThatFits(region), animated: true)
            
            let annotation = MKPointAnnotation()
            
            annotation.coordinate = coords
            annotation.title = String(format: "%.2f meters", altitude)
            
            mapView.addAnnotation(annotation)
            annotations.append(annotation)
                        
            last_lat = lat
            last_lon = lon
            
            current_location = lastLocation
        }
        
    }
}

class DatabaseService{
    static var shared = DatabaseService()
    var container: ModelContainer?
    var context: ModelContext?
    
    init(){
        
        do{
            
            container = try ModelContainer(for: [LocationModel.self])
            
            if let container{
                context = ModelContext(container)
            }
        }
        catch{
            print(error)
        }
    }
    
    func saveLocation(location: CLLocation?) {
        
        guard let location else{
            return
        }
        
        if let context{

            let coords = location.coordinate
            let latitude = coords.latitude
            let longitude = coords.longitude
            let altitude = location.altitude
            
            let LocationToBeSaved = LocationModel(id: UUID().uuidString, latitude: latitude, longitude: longitude, altitude: altitude, time: Date().timeIntervalSince1970)
            
            context.insert(object: LocationToBeSaved)
        }
    }
    
    func fetchLocations(onCompletion:@escaping([LocationModel]?,Error?)->(Void)){
        
        let descriptor = FetchDescriptor<LocationModel>(sortBy: [SortDescriptor<LocationModel>(\.time)])
        
        if let context{
            do{
                let data = try context.fetch(descriptor)
                onCompletion(data,nil)
            }
            catch{
                onCompletion(nil,error)
            }
        }
    }
    
    func updateLocation(Location: LocationModel,newLocation: LocationModel){
        // Not implemented. It's not a thing we need to do.
    }
    
    func deleteLocation(Location: LocationModel){
        let LocationToBeDeleted = Location
        if let context{
            context.delete(LocationToBeDeleted)
        }
    }
}
