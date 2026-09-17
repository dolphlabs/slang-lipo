// domain/user — repository port placeholder (sqlite repo used directly).

pub gc struct UserRepository {
    _pad: int
}

pub fn new_user_repository() -> UserRepository {
    return UserRepository { _pad: 0 };
}
