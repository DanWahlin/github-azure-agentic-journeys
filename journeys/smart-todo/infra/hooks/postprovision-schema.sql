-- SmartTodo schema + seed data (see PLAN.md: Database Schema and Seed Data).
-- Idempotent: safe to run more than once.

IF OBJECT_ID('Todos', 'U') IS NULL
BEGIN
    CREATE TABLE Todos (
        id NVARCHAR(36) PRIMARY KEY,
        title NVARCHAR(500) NOT NULL,
        status NVARCHAR(20) NOT NULL DEFAULT 'pending',
        userId NVARCHAR(100) NOT NULL,
        stepsGenerated BIT NOT NULL DEFAULT 0,
        createdAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        updatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    );

    CREATE INDEX IX_Todos_UserId ON Todos(userId);
END;

IF OBJECT_ID('ActionSteps', 'U') IS NULL
BEGIN
    CREATE TABLE ActionSteps (
        id NVARCHAR(36) PRIMARY KEY,
        todoId NVARCHAR(36) NOT NULL,
        title NVARCHAR(200) NOT NULL,
        description NVARCHAR(1000) NOT NULL,
        [order] INT NOT NULL,
        isCompleted BIT NOT NULL DEFAULT 0,
        createdAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CONSTRAINT FK_ActionSteps_Todos FOREIGN KEY (todoId) REFERENCES Todos(id) ON DELETE CASCADE
    );

    CREATE INDEX IX_ActionSteps_TodoId ON ActionSteps(todoId);
END;

IF NOT EXISTS (SELECT 1 FROM Todos)
BEGIN
    INSERT INTO Todos (id, title, status, userId, stepsGenerated) VALUES
        ('todo-1', 'Prepare Conference talk', 'pending', 'user-1', 0),
        ('todo-2', 'Set up home office', 'in_progress', 'user-1', 1),
        ('todo-3', 'Plan weekend hiking trip', 'completed', 'user-1', 1);

    INSERT INTO ActionSteps (id, todoId, title, description, [order], isCompleted) VALUES
        ('step-2-1', 'todo-2', 'Choose a desk and chair', 'Pick a desk and an ergonomic chair that fit your space and budget.', 1, 1),
        ('step-2-2', 'todo-2', 'Set up monitor and peripherals', 'Position your monitor at eye level and connect the keyboard, mouse, and webcam.', 2, 1),
        ('step-2-3', 'todo-2', 'Organize cable management', 'Route and fasten cables with ties or a cable tray to keep the desk clear.', 3, 0),
        ('step-2-4', 'todo-2', 'Set up lighting', 'Add a desk lamp or ring light so your workspace and video calls are well lit.', 4, 0),
        ('step-3-1', 'todo-3', 'Pick a trail', 'Choose a trail that matches your fitness level and check its length and elevation.', 1, 1),
        ('step-3-2', 'todo-3', 'Check weather forecast', 'Review the weekend forecast for the trailhead area and plan around it.', 2, 1),
        ('step-3-3', 'todo-3', 'Pack gear and supplies', 'Pack water, snacks, layers, a first-aid kit, and a map or GPS app.', 3, 1);
END;
