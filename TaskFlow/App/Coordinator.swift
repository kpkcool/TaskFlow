//
//  Coordinator.swift
//  TaskFlow
//
//  ViewControllers never push/present other ViewControllers directly —
//  every navigation decision flows through a Coordinator.
//

import UIKit

@MainActor
protocol Coordinator: AnyObject {
    func start()
}
