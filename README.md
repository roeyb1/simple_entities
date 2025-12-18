# simple_entities

A very simple entity system for the Jai programming language.


Note: the metaprogram plugin included here currently does _not_ work due to difficulty in passing the type definitions across the program module boundary and into the `simple_entities` module. If you wish to use this in your own projects, just rip out the message loop from the metaprogram plugin and insert into your own metaprogram mesage loop.

# Background

While iterating on designs for the entity system for the game, I experimented with an ECS framework. I definitely enjoy the performance aspects, separate of data/logic, ease of serializing game state, network synchronization, (many more benefits). However, it became apparent that (outside of the rendering code) the ECS soon became the largest part of the codebase. The complexity of managing the ECS vastly out-weighed the benefits of having such a dynamic system.
I wanted to try to find a solution which had some of the organizational benefits of an ECS, while keeping gameplay iteration times fast and code complexity low.

Thinking along those lines, some of the things I missed from non-ECS frameworks were:
- Being able to easily inspect the entire state of any entity in the debugger at any time
	- (Component data is spread through memory and accessed by index thus can't be easily reconstructed in a debugger)
- The ability to think about entities as a whole rather than only ever considering sparse data
	- (An entity's "type" is defined by the set of components it owns. This can change dynamically at runtime and depending how fine-grained components are made it can be very hard to reason about the state of that type at any given time)
- ECS tends to give rise to a lot of tiny systems each doing a small chunk of the overall work. This is mostly due to the typical ECS style being to break up data into components using the smallest possible subsets of the data. This can make it very hard to track the flow of data within a single process from beginning to end.
- All components of the same type in an ECS _want_ to be treated in the same way in all cases but that isn't always correct or convenient. A simple example might be if I wanted to disable replication of the inventory component on enemies but not on players. It's not very "ECS" to enable replication for all inventories only if they are on the "player" archetype (then that brings the other issue of what is a "player" if not defined by some concrete type...). This tends to create a lot of duplicated component types which only differ by name. Eg: `PlayerInventory`, `EnemyInventory`, even though you were hoping to share code between them, now you can't. 

# My Solution

The base Entity class in my engine is a very lightweight struct which contains data that all entities should have. It looks a bit like this:
```jai
Entity :: struct {
	name: Name;
	id: Entity_ID;
	flags: Entity_Flags;
	position: Position;
}
```

A specialized entity type may look something like this:
```jai
Player :: struct {
	#insert #run as_base_entity(); // "inherits" from base entity type and has optional parameters for how this entity should be stored.
	
	velocity: Velocity;
	health: Health,
	inventory: Inventory;
}
```

Entities are stored in cache-friendly contiguous arrays grouped by entity type. This is very close to how entities are stored in an archetype-ECS in a table-style approach with the caveat that the entity struct is still stored AoS instead of SoA. This is also something Jai can help with as its very easy to swap the backing data representation from an AoS to an SoA with minimal cascading code changes. Something like a `Bucket_SoA` could easily be implemented which groups all the members of each fragment into their own array. However, I think this needs further testing though to ensure this is even worth doing. If entity types remain relatively small it is unlikely that there would be a significant performance impact in doing this. Though for SIMD it may definitely be useful to decompose the members of each "fragment" into its members.

What's interesting about this approach is that we can start to consider entities as structured units again, more akin to the OOP world model which feels more natural for gameplay code. By providing a few abstractions on top of this entity model we can reach the flexibility of the ECS component data design without all the complexity of managing complex archetypes and sparse storage systems.

## Queries

We can create the same database-style query system that an ECS is built on through some basic reflection systems. Querying all entities with a given subset of "fragments" and operating on all of them in an efficient data-oriented loop.

```jai
// update the position of all entities based on their velocities
for view : each_entity_with(world, *Position, Velocity) {
	view._Position += view._Velocity * delta_time ;
}
```

Operating on all entities of a named type is also possible by directly iterating over the entity storage buffers:

```jai
// adding some item to all player inventories
for player : each_entity(world, Player) {
	add_item(*player.inventory, Item.{...});
}
```

In short, `Queries` give the game designer the **option** to choose the specific cases where writing generic code per-type makes sense and when special behavior per-entity type is required they can still do that without polluting the type system.

## Sparse storage (not yet implemented)

Something that doesn't immediately seem possible with this type of approach is the ability to optionally add some data some entities in a type but not all. There's a couple ways this can be solved. 
The first most trivial solution is to put the optional data on the entity struct and add a flag to indicate if the entity has that data or not:
```jai
Player :: struct {
	//...
	mount_info: Mount_Info; // describes the mount the player is riding
	has_mount: bool;
}
```

However with this approach you of course pay the cost of allocating memory for that `mount_info` for every player. This may not really be an issue in practice, but it can be solved with our system fairly easily.

Another place where Jai helps us out here is the convenience factor that pointers are auto-dereferenced with the `.` operator rather than the C++ conventional `->` operator. This allow us to pretty transparently-to-users modify the `mount_info` member to be a `*Mount_Info` instead.

```jai
Player :: struct {
	//...
	mount_info: *Mount_Info; @Sparse @Optional
}
```

The entity system also implements a sparse storage solution so all `mount_infos` are allocated from a common per-type pool. This side-car data is entirely optional per-entity and can be constructed dynamically as well at a later time.

```jai
mount :: (player: *Player, mount_info: Mount_Info) {
	player.mount_info = alloc_fragment(mount_info);
}
```

This solution also works to reduce entity sizes when needed by moving potentially cold data off the entity and into sparse storage sets. It could also be used to improve the cache efficiency of some select very hot code paths such as physics by moving all physics info into a single sidecar buffer which would be cache efficient for the physics system.
