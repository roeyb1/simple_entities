each_entity :: (entities: *Entity_Manager, $Entity_Type: Type) -> Entity_Iter(Entity_Type) {
    return .{ entities = entities };
}

for_expansion :: (iter: Entity_Iter, body: Code, flags: For_Flags) #expand {
    array := array_for_entity_type(*iter.entities.by_type, iter.Entity_Type);

    `it: *iter.Entity_Type;
    `it_index: Entity_Locator;
    for entity, locator : array {
        it = entity;
        it_index = locator;
        #insert (break=break, remove={ handle := make_handle(iter.entities, it, it_index); destroy_entity(iter.entities, handle); }) body;
    }
}

Entity_Iter :: struct(Entity_Type: Type) {
    entities: *Entity_Manager;
}
