import React, { useState, useEffect } from "react";
import { Card, Button } from "./ui";

type User = {
  id: string;
  name: string;
  active: boolean;
};

interface Props {
  title: string;
  users: User[];
  onSelect?: (id: string) => void;
}

export function UserList({ title, users, onSelect }: Props) {
  const [query, setQuery] = useState("");
  const [filtered, setFiltered] = useState<User[]>(users);

  useEffect(() => {
    const q = query.trim().toLowerCase();
    setFiltered(
      users.filter((u) => u.name.toLowerCase().includes(q) && u.active)
    );
  }, [query, users]);

  return (
    <Card className="user-list">
      <header className="header">
        <h1>{title}</h1>
        <input
          value={query}
          placeholder="Search users…"
          onChange={(e) => setQuery(e.target.value)}
        />
      </header>
      <>
        {filtered.length === 0 ? (
          <p className="empty">No matches</p>
        ) : (
          <ul>
            {filtered.map((user) => (
              <li key={user.id}>
                <Button onClick={() => onSelect?.(user.id)}>
                  {user.name}
                </Button>
              </li>
            ))}
          </ul>
        )}
      </>
    </Card>
  );
}

export default UserList;
