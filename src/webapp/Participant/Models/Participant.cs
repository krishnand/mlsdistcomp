using System;

namespace MRSDistCompWebApp.Models
{
    public class Participant
    {
        public Guid Id { get; set; }
        public string Name { get; set; }       
        public Guid ClientId { get; set; }
        public string TenantId { get; set; }
        public string URL { get; set; }
        public string ClientSecret { get; set; }
        public bool IsEnabled { get; set; }
        public DateTime ValidFrom { get; set; }
        public DateTime ValidTo { get; set; }
    }
}
