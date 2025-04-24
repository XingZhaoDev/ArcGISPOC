import UIKit
import ArcGIS

class DemoViewController: UIViewController {
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Demo View Controller"
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 20, weight: .bold)
        return label
    }()
    
    var rectangleGraphic: AGSGraphic?
    private var pointsOverlay = AGSGraphicsOverlay()
    private var drawingOverlay = AGSGraphicsOverlay()
    private var startPoint: CGPoint?
    private var panGestureRecognizer: UIPanGestureRecognizer?
    private var isDrawingEnabled = false
    
    private lazy var mapView: AGSMapView = {
        let mapView = AGSMapView()
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.map = AGSMap(basemapStyle: .arcGISChartedTerritory)
        return mapView
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupMapView()
        setupNavigationBar()
        setupPanGesture()
        loadSavedPoints()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Demo"
    }
    
    private func setupNavigationBar() {
        let drawButton = UIBarButtonItem(title: "Draw",
                                       style: .plain,
                                       target: self,
                                       action: #selector(drawButtonTapped))
        navigationItem.rightBarButtonItem = drawButton
    }
    
    @objc private func drawButtonTapped() {
        isDrawingEnabled.toggle()
        navigationItem.rightBarButtonItem?.title = isDrawingEnabled ? "Cancel" : "Draw"
        panGestureRecognizer?.isEnabled = isDrawingEnabled
        mapView.interactionOptions.isPanEnabled = !isDrawingEnabled
        
        if !isDrawingEnabled {
            drawingOverlay.graphics.removeAllObjects()
        }
        
        print("Drawing mode: \(isDrawingEnabled)")
    }
    
    private func setupMapView() {
        view.addSubview(mapView)
        
        mapView.graphicsOverlays.removeAllObjects()
        
        drawingOverlay.opacity = 1.0
        drawingOverlay.isVisible = true
        pointsOverlay.opacity = 1.0
        pointsOverlay.isVisible = true
        
        mapView.graphicsOverlays.addObjects(from: [pointsOverlay, drawingOverlay])
        
        mapView.setViewpoint(AGSViewpoint(
            center: AGSPoint(x: -123.1207, y: 49.2827, spatialReference: .wgs84()),
            scale: 25000,
            rotation: 0
        ))
        
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupPanGesture() {
        panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGestureRecognizer?.isEnabled = false
        if let panGesture = panGestureRecognizer {
            mapView.addGestureRecognizer(panGesture)
        }
    }
    
    /*@objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: mapView)
        
        switch gesture.state {
        case .began:
            startPoint = location
            drawingOverlay.graphics.removeAllObjects()
            print("Pan began at screen point: \(location)")
            
        case .changed:
            guard let start = startPoint else { return }
            print("Pan changed to screen point: \(location)")
            
            // Convert screen points to map points
            let startMapPoint = mapView.screen(toLocation: start)
            let currentMapPoint = mapView.screen(toLocation: location)
            
            let minX = min(startMapPoint.x, currentMapPoint.x)
            let maxX = max(startMapPoint.x, currentMapPoint.x)
            let minY = min(startMapPoint.y, currentMapPoint.y)
            let maxY = max(startMapPoint.y, currentMapPoint.y)
            
            let polygon = AGSPolygonBuilder(spatialReference: .wgs84())
            polygon.addPointWith(x: minX, y: minY)
            polygon.addPointWith(x: maxX, y: minY)
            polygon.addPointWith(x: maxX, y: maxY)
            polygon.addPointWith(x: minX, y: maxY)
            polygon.addPointWith(x: minX, y: minY)
            
            drawingOverlay.graphics.removeAllObjects()
            
            let lineSymbol = AGSSimpleLineSymbol(style: .solid, color: .red, width: 2)
            let fillSymbol = AGSSimpleFillSymbol(
                style: .solid,
                color: UIColor.blue.withAlphaComponent(0.3),
                outline: lineSymbol
            )
            
            let graphic = AGSGraphic(geometry: polygon.toGeometry(), symbol: fillSymbol)
            drawingOverlay.graphics.add(graphic)
            print("Added rectangle: \(minX),\(minY) to \(maxX),\(maxY)")
            
        case .ended:
            print("Pan ended")
            break
            
        default:
            break
        }
    }*/
    
    @objc func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
           let currentPoint = gesture.location(in: mapView)
           
           switch gesture.state {
           case .began:
               startPoint = currentPoint
               removeExistingRectangle()
           case .changed:
               if let startPoint {
                   drawRectangle(from: startPoint, to: currentPoint)
               }
           case .ended, .cancelled:
               startPoint = nil
           default:
               break
           }
       }

       func drawRectangle(from p1: CGPoint, to p2: CGPoint) {
           let mapPoint1 = mapView.screen(toLocation: p1)
            let mapPoint2 = mapView.screen(toLocation: p2)

           // Define all 4 corners based on bounding box
           let minX = min(mapPoint1.x, mapPoint2.x)
           let maxX = max(mapPoint1.x, mapPoint2.x)
           let minY = min(mapPoint1.y, mapPoint2.y)
           let maxY = max(mapPoint1.y, mapPoint2.y)

           let builder = AGSPolygonBuilder(spatialReference: mapPoint1.spatialReference)

           builder.addPointWith(x: minX, y: minY) // bottom-left
           builder.addPointWith(x: minX, y: maxY) // top-left
           builder.addPointWith(x: maxX, y: maxY) // top-right
           builder.addPointWith(x: maxX, y: minY) // bottom-right
           builder.addPointWith(x: minX, y: minY) // close polygon

           let polygon = builder.toGeometry()
           let fillSymbol = AGSSimpleFillSymbol(
               style: .solid,
               color: UIColor.blue.withAlphaComponent(0.3),
               outline: AGSSimpleLineSymbol(style: .dash, color: .orange, width: 1)
           )

           if let rectangleGraphic {
               rectangleGraphic.geometry = polygon
           } else {
               let graphic = AGSGraphic(geometry: polygon, symbol: fillSymbol)
               drawingOverlay.graphics.add(graphic)
               rectangleGraphic = graphic
           }
       }

       func removeExistingRectangle() {
           if let graphic = rectangleGraphic {
               drawingOverlay.graphics.remove(graphic)
               rectangleGraphic = nil
           }
       }
    
    private func loadSavedPoints() {
        guard let jsonData = UserDefaults.standard.data(forKey: "savedPoints") else { return }
        
        do {
            if let pointsArray = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]] {
                if let appleImage = UIImage(named: "applelogo") {
                    let markerSymbol = AGSPictureMarkerSymbol(image: appleImage)
                    markerSymbol.width = 20
                    markerSymbol.height = 20
                    
                    for pointDict in pointsArray {
                        if let latitude = pointDict["latitude"] as? Double,
                           let longitude = pointDict["longitude"] as? Double {
                            let point = AGSPoint(x: longitude, y: latitude, spatialReference: .wgs84())
                            let graphic = AGSGraphic(geometry: point, symbol: markerSymbol, attributes: pointDict["attributes"] as? [String: Any])
                            pointsOverlay.graphics.add(graphic)
                        }
                    }
                }
            }
        } catch {
            print("Failed to load saved points: \(error)")
        }
    }
}
