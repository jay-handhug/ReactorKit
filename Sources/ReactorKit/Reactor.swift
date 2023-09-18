//
//  Reactor.swift
//  ReactorKit
//
//  Created by Suyeol Jeon on 06/04/2017.
//  Copyright © 2017 Suyeol Jeon. All rights reserved.
//

import RxSwift
import WeakMapTable

@available(*, obsoleted: 0, renamed: "Never")
public typealias NoAction = Never

@available(*, obsoleted: 0, renamed: "Never")
public typealias NoMutation = Never

/// A Reactor is an UI-independent layer which manages the state of a view. The foremost role of a
/// reactor is to separate control flow from a view. Every view has its corresponding reactor and
/// delegates all logic to its reactor. A reactor has no dependency to a view, so it can be easily
/// tested.
public protocol Reactor: AnyObject {
  /// An action represents user actions.
  associatedtype Action
  
  /// A State represents the current state of a view.
  associatedtype State
  
  typealias Scheduler = ImmediateSchedulerType
  
  /// The action from the view. Bind user inputs to this subject.
  var action: ActionSubject<Action> { get }
  
  /// The initial state.
  var initialState: State { get }
  
  /// The current state. This value is changed just after the state stream emits a new state.
  var currentState: State { get }
  
  /// The state stream. Use this observable to observe the state changes.
  var state: Observable<State> { get }
  
  /// Generates a new state with the previous state and the action. It should be purely functional
  /// so it should not perform any side-effects here. This method is called every time when the
  /// mutation is committed.
  func reduce(state: inout State, action: Action) -> Observable<Action>
}


// MARK: - Map Tables

private typealias AnyReactor = AnyObject

private enum MapTables {
  static let action = WeakMapTable<AnyReactor, AnyObject>()
  static let currentState = WeakMapTable<AnyReactor, Any>()
  static let state = WeakMapTable<AnyReactor, AnyObject>()
  static let disposeBag = WeakMapTable<AnyReactor, DisposeBag>()
  static let isStubEnabled = WeakMapTable<AnyReactor, Bool>()
  static let stub = WeakMapTable<AnyReactor, AnyObject>()
}


// MARK: - Default Implementations

extension Reactor {
  private var _action: ActionSubject<Action> {
    if isStubEnabled {
      return stub.action
    } else {
      return MapTables.action.forceCastedValue(forKey: self, default: .init())
    }
  }
  
  public var action: ActionSubject<Action> {
    // Creates a state stream automatically
    _ = _state
    
    // It seems that Swift has a bug in associated object when subclassing a generic class. This is
    // a temporary solution to bypass the bug. See #30 for details.
    return _action
  }
  
  public internal(set) var currentState: State {
    get { MapTables.currentState.forceCastedValue(forKey: self, default: initialState) }
    set { MapTables.currentState.setValue(newValue, forKey: self) }
  }
  
  private var _state: Observable<State> {
    if isStubEnabled {
      return stub.state.asObservable()
    } else {
      return MapTables.state.forceCastedValue(forKey: self, default: createStateStream())
    }
  }
  
  public var state: Observable<State> {
    // It seems that Swift has a bug in associated object when subclassing a generic class. This is
    // a temporary solution to bypass the bug. See #30 for details.
    _state
  }
  
  fileprivate var disposeBag: DisposeBag {
    MapTables.disposeBag.value(forKey: self, default: DisposeBag())
  }
  
  public func createStateStream() -> Observable<State> {
    let action = _action.asObservable()
    let state = action
      .scan(initialState) { [weak self] state, action -> State in
        guard let self = self else { return state }
        var state = state
        let nextAction = self.reduce(state: &state, action: action)
        nextAction
          .subscribe(onNext: { action in
            self.action.onNext(action)
          })
          .disposed(by: self.disposeBag)
        
        return state
      }
      .catch { _ in .empty() }
      .startWith(initialState)
    
    let replayState = state
      .do(onNext: { [weak self] state in
        self?.currentState = state
      })
      .replay(1)
      replayState.connect().disposed(by: disposeBag)
      return replayState.subscribe(on: MainScheduler.instance)
  }
}

// MARK: - Stub

extension Reactor {
  public var isStubEnabled: Bool {
    get { MapTables.isStubEnabled.value(forKey: self, default: false) }
    set { MapTables.isStubEnabled.setValue(newValue, forKey: self) }
  }
  
  public var stub: Stub<Self> {
    MapTables.stub.forceCastedValue(forKey: self, default: .init(reactor: self, disposeBag: disposeBag))
  }
}



