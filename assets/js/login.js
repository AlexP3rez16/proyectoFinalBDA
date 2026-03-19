document.addEventListener('DOMContentLoaded', function() {
    
    const loginForm = document.getElementById('loginForm');

    if (loginForm) {
        loginForm.addEventListener('submit', function(e) {
            e.preventDefault(); // Evita que el formulario se envíe de forma tradicional
            
            const emailInput = document.getElementById('email');
            const email = emailInput.value.toLowerCase();
            
            let destination = '';

            // Lógica simple de enrutamiento basada en el contenido del email
            if (email.includes('admin')) {
                destination = 'admin/admin-dashboard.html';
            } else if (email.includes('doctor') || email.includes('medico')) {
                destination = 'medico/dashboard.html';
            } else if (email.includes('cuidador')) {
                destination = 'cuidador/dashboard.html';
            } else {
                // Por defecto (o si no se reconoce la palabra clave)
                destination = 'medico/dashboard.html';
            }

            console.log("Redirigiendo a:", destination);

            // Redirección al dashboard correspondiente
            window.location.href = destination;
        });
    }
});